import Foundation
import Testing
import StoneDomain
@testable import StoneApplication

struct NoteSearchIndexerTests {
    @Test func failedWorkspaceScanPreservesPreviouslyIndexedNotes() async throws {
        let repo = SearchTestRepository(["a.md": "# A\n\nkeep indexed"])
        let index = SearchTestIndex()
        let indexer = NoteSearchIndexer(repository: repo, policy: .standard, index: index)
        try await indexer.refresh()
        await repo.failListing()
        await #expect(throws: SearchTestError.self) { try await indexer.refresh() }
        #expect(await index.notes.count == 1)
        #expect(await index.notes[try NotePath("a.md")]?.body == "keep indexed")
    }
    @Test func nextSearchRepairsPreviouslyFailedCaptureIndexing() async throws {
        let repo = SearchTestRepository(["a.md": "# Old\n\nexisting"])
        let index = SearchTestIndex()
        let indexer = NoteSearchIndexer(repository: repo, policy: .standard, index: index)
        try await indexer.refresh()
        await index.fail()
        let clock = FixedClock(2026, 9, 30)
        let journal = createJournalUseCases(repository: repo, clock: clock, policy: .standard, indexer: indexer)
        _ = try await journal.capture("recoverable capture", writtenAt: clock.now)
        await indexer.waitForPendingEmbeddings()
        await index.recover()
        let search = createSearchUseCases(repository: repo, policy: .standard, index: index, indexer: indexer)
        #expect(try await search.search("recoverable", limit: 10).count == 1)
        #expect(await repo.readCount == 2)
    }

    @Test func unreadableFileDoesNotPreventLaterFilesBeingIndexed() async throws {
        let repo = SearchTestRepository(["a.md": "# A", "b.md": "# B", "c.md": "# C"])
        await repo.failReads("a.md")
        let index = SearchTestIndex()
        let indexer = NoteSearchIndexer(repository: repo, policy: .standard, index: index)
        try await indexer.refresh()
        #expect(await index.notes.keys.map(\.value).sorted() == ["b.md", "c.md"])
        #expect(await repo.readCount == 3)
    }

    @Test func captureQueuedDuringRefreshWinsOverItsOlderSnapshot() async throws {
        let path = "Journal/2026-09-30.md"
        let repo = SearchTestRepository([path: "# 2026-09-30\n\nold"])
        let index = SearchTestIndex()
        let indexer = NoteSearchIndexer(repository: repo, policy: .standard, index: index)
        await repo.blockNextRead(path)
        let refresh = Task { try await indexer.refresh() }
        await repo.waitUntilReadBlocked()
        let clock = FixedClock(2026, 9, 30)
        let journal = createJournalUseCases(repository: repo, clock: clock, policy: .standard, indexer: indexer)
        _ = try await journal.capture("latest capture", writtenAt: clock.now)
        await repo.releaseRead()
        try await refresh.value
        try await indexer.prepareForSearch()
        #expect(await index.notes[try NotePath(path)]?.body.contains("latest capture") == true)
    }

    @Test func unsupportedInputCannotStarveLaterEmbeddingBatches() async throws {
        var files = ["00.md": "# First\n\nunsupported"]
        for number in 1...34 { files["\(number).md"] = "# Note \(number)\n\nsearchable" }
        let repo = SearchTestRepository(files)
        let index = SearchTestIndex()
        let embedder = SelectiveSearchEmbedder()
        let indexer = NoteSearchIndexer(repository: repo, policy: .standard, index: index, embedder: embedder)
        try await indexer.refresh()
        await indexer.waitForPendingEmbeddings()
        #expect(await index.storedEmbeddings == 34)
        #expect(await embedder.calls == 35)
        #expect(try await index.pendingEmbeddings(modelIdentifier: embedder.modelIdentifier, limit: 20).count == 1)
    }

    @Test func refreshReadsOnlyChangesAndPrunesDeletedNotes() async throws {
        let repo = SearchTestRepository(["a.md": "# A\n\none", "b.md": "# B\n\ntwo"])
        let index = SearchTestIndex()
        let indexer = NoteSearchIndexer(repository: repo, policy: .standard, index: index)
        try await indexer.refresh()
        #expect(await repo.readCount == 2)
        try await indexer.refresh()
        #expect(await repo.readCount == 2)
        try await repo.write("# A\n\nupdated", to: NotePath("a.md"))
        try await repo.write("# C\n\nnew", to: NotePath("c.md"))
        await repo.remove("b.md")
        try await indexer.refresh()
        #expect(await repo.readCount == 4)
        #expect(await index.notes.keys.map(\.value).sorted() == ["a.md", "c.md"])
        #expect(await index.notes[try NotePath("a.md")]?.body == "updated")
    }

    @Test func captureReturnsDuringEmbeddingAndNewTextReplacesStaleJobs() async throws {
        let path = "Journal/2026-09-30.md"
        let repo = SearchTestRepository([path: "# 2026-09-30\n\nold"])
        let index = SearchTestIndex()
        let embedder = BlockingSearchEmbedder()
        let indexer = NoteSearchIndexer(repository: repo, policy: .standard, index: index, embedder: embedder)
        try await indexer.refresh()
        await embedder.waitUntilStarted()
        let clock = FixedClock(2026, 9, 30)
        let journal = createJournalUseCases(repository: repo, clock: clock, policy: .standard, indexer: indexer)
        let note = try await journal.capture("new searchable thought", writtenAt: clock.now)
        #expect(note.body.contains("new searchable thought"))
        try await indexer.prepareForSearch()
        #expect(await index.notes[try NotePath(path)]?.body.contains("new searchable thought") == true)
        #expect(await index.storedEmbeddings == 0)
        await embedder.release()
        await indexer.waitForPendingEmbeddings()
        #expect(await index.attemptedEmbeddings == 2)
        #expect(await index.storedEmbeddings == 1)
        #expect(await embedder.maxActive == 1)
        #expect(try await index.pendingEmbeddings(modelIdentifier: embedder.modelIdentifier, limit: 10).isEmpty)
    }

    @Test func unavailableModelStopsAndRetriesAtNextRefresh() async throws {
        let repo = SearchTestRepository(["a.md": "# A\n\nthought"])
        let index = SearchTestIndex()
        let embedder = UnavailableSearchEmbedder()
        let indexer = NoteSearchIndexer(repository: repo, policy: .standard, index: index, embedder: embedder)
        try await indexer.refresh()
        await indexer.waitForPendingEmbeddings()
        #expect(await embedder.calls == 1)
        #expect(await index.upsertCount == 1)
        try await indexer.refresh()
        await indexer.waitForPendingEmbeddings()
        #expect(await embedder.calls == 2)
        #expect(await index.upsertCount == 1)
    }

    @Test func blankAndFailedCapturesNeverEnterIndex() async throws {
        let repo = SearchTestRepository()
        let index = SearchTestIndex()
        let indexer = NoteSearchIndexer(repository: repo, policy: .standard, index: index)
        let clock = FixedClock(2026, 9, 30)
        let journal = createJournalUseCases(repository: repo, clock: clock, policy: .standard, indexer: indexer)
        _ = try await journal.capture(" \n ", writtenAt: clock.now)
        await indexer.waitForPendingEmbeddings()
        #expect(await index.upsertCount == 0)
        await repo.failWrites()
        await #expect(throws: SearchTestError.self) { try await journal.capture("not saved", writtenAt: clock.now) }
        await indexer.waitForPendingEmbeddings()
        #expect(await index.upsertCount == 0)
    }

    @Test func failedCacheDoesNotFailSuccessfulCapture() async throws {
        let repo = SearchTestRepository()
        let index = SearchTestIndex()
        await index.fail()
        let indexer = NoteSearchIndexer(repository: repo, policy: .standard, index: index)
        let clock = FixedClock(2026, 9, 30)
        let journal = createJournalUseCases(repository: repo, clock: clock, policy: .standard, indexer: indexer)
        let note = try await journal.capture("saved", writtenAt: clock.now)
        await indexer.waitForPendingEmbeddings()
        #expect(note.body.contains("saved"))
        #expect(await repo.writeCount == 1)
    }

    @Test func firstSearchIndexesAndRepeatedSearchDoesNotReadBodies() async throws {
        let repo = SearchTestRepository(["a.md": "# Wallet\n\nrelease"])
        let index = SearchTestIndex()
        let indexer = NoteSearchIndexer(repository: repo, policy: .standard, index: index)
        let search = createSearchUseCases(repository: repo, policy: .standard, index: index, indexer: indexer)
        #expect(try await search.search("wallet", limit: 10).count == 1)
        #expect(try await search.search("release", limit: 10).count == 1)
        #expect(await repo.readCount == 1)
        #expect(await index.candidateCalls == 2)
        #expect(try await search.search("wallet", limit: -1).isEmpty)
    }

    @Test func failedIndexFallsBackToFilesystemButFailedModelKeepsLexicalIndex() async throws {
        let repo = SearchTestRepository(["a.md": "# Wallet\n\nrelease"])
        let index = SearchTestIndex()
        let indexer = NoteSearchIndexer(repository: repo, policy: .standard, index: index)
        let search = createSearchUseCases(
            repository: repo, policy: .standard, index: index, indexer: indexer,
            embedder: FailingSearchEmbedder(cancelled: false))
        #expect(try await search.search("wallet", limit: 10).count == 1)
        #expect(await index.candidateCalls == 1)
        await index.fail()
        #expect(try await search.search("wallet", limit: 10).count == 1)
        #expect(await repo.readCount == 2)
    }

    @Test func cancellationNeverStartsFilesystemFallback() async throws {
        let repo = SearchTestRepository(["a.md": "# Wallet\n\nrelease"])
        let index = SearchTestIndex()
        let search = createSearchUseCases(
            repository: repo, policy: .standard, index: index,
            embedder: FailingSearchEmbedder(cancelled: true))
        await #expect(throws: CancellationError.self) { try await search.search("wallet", limit: 10) }
        #expect(await repo.readCount == 0)
        #expect(await index.candidateCalls == 0)
    }
}
