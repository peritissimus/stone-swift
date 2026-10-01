import Foundation
import Testing
import StoneDomain
@testable import StoneApplication

struct JournalUseCaseTests {
    @Test func captureSeedsTodayThenAppends() async throws {
        let repo = InMemoryNoteRepository()
        let clock = FixedClock(2026, 9, 30, 15, 35)
        let journal = createJournalUseCases(repository: repo, clock: clock, policy: .standard)
        _ = try await journal.capture("followup leak", writtenAt: clock.now)
        let note = try await journal.capture("add sql", writtenAt: clock.now)
        #expect(note.title == "2026-09-30")
        #expect(repo.source("Journal/2026-09-30.md") == "# 2026-09-30\n\n[15:35] followup leak\n\n[15:35] add sql")
    }

    @Test func captureKeepsTheExistingFileByteForByte() async throws {
        let original = "---\ntags: [daily]\n---\n\n# 2026-09-30\n\n\n[09:00] early"
        let repo = InMemoryNoteRepository(["Journal/2026-09-30.md": original])
        let clock = FixedClock(2026, 9, 30, 10, 5)
        let journal = createJournalUseCases(repository: repo, clock: clock, policy: .standard)
        _ = try await journal.capture("later", writtenAt: clock.now)
        #expect(repo.source("Journal/2026-09-30.md") == original + "\n\n[10:05] later")
    }

    @Test func blankCaptureWritesNothing() async throws {
        let repo = InMemoryNoteRepository()
        let clock = FixedClock(2026, 9, 30)
        let journal = createJournalUseCases(repository: repo, clock: clock, policy: .standard)
        _ = try await journal.capture("   \n ", writtenAt: clock.now)
        #expect(repo.source("Journal/2026-09-30.md") == nil)
    }

    @Test func captureUsesTheMomentItWasWrittenNotWhenItRuns() async throws {
        let repo = InMemoryNoteRepository()
        let clock = FixedClock(2026, 10, 1, 0, 0)
        let journal = createJournalUseCases(repository: repo, clock: clock, policy: .standard)
        let lateLastNight = FixedClock(2026, 9, 30, 23, 59).now
        let note = try await journal.capture("late thought", writtenAt: lateLastNight)
        #expect(note.path.value == "Journal/2026-09-30.md")
        #expect(repo.source("Journal/2026-09-30.md") == "# 2026-09-30\n\n[23:59] late thought")
    }

    @Test func todayNeverCreatesTheFile() async throws {
        let repo = InMemoryNoteRepository()
        let clock = FixedClock(2026, 9, 30)
        let journal = createJournalUseCases(repository: repo, clock: clock, policy: .standard)
        #expect(try await journal.today() == nil)
        #expect(repo.source("Journal/2026-09-30.md") == nil)
    }

    @Test func honoursTheConfiguredJournalFolder() async throws {
        let repo = InMemoryNoteRepository()
        let policy = LocationPolicy(journalFolder: "Daily")
        let clock = FixedClock(2026, 9, 30, 8, 0)
        let journal = createJournalUseCases(repository: repo, clock: clock, policy: policy)
        let note = try await journal.capture("hi", writtenAt: clock.now)
        #expect(note.path.value == "Daily/2026-09-30.md")
        #expect(note.isJournal)
    }
}

struct NoteUseCaseTests {
    @Test func listsNewestFirstAndOpensReadOnly() async throws {
        let repo = InMemoryNoteRepository(["Personal/a.md": "# Old\n\none", "Personal/b.md": "# New\n\ntwo"])
        let notes = createNoteUseCases(repository: repo, policy: .standard)
        #expect(try await notes.listNotes().map(\.title) == ["New", "Old"])
        #expect(try await notes.openNote(try NotePath("Personal/a.md")).body == "one")
        await #expect(throws: NoteError.self) { try await notes.openNote(try NotePath("Personal/missing.md")) }
    }
}

struct SearchUseCaseTests {
    @Test func ranksTitleHitsFirst() async throws {
        let repo = InMemoryNoteRepository([
            "Personal/a.md": "# Other\n\nwallet mentioned",
            "Personal/b.md": "# Wallet release\n\n",
            "Personal/c.md": "# Nope\n\n",
        ])
        let search = createSearchUseCases(repository: repo, policy: .standard)
        let hits = try await search.search("wallet", limit: 10)
        #expect(hits.map(\.note.title) == ["Wallet release", "Other"])
    }
}
