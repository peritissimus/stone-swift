import Foundation
import Testing
import StoneDomain
@testable import StoneApplication

struct NeuralSearchTests {
    @Test func neuralRerankingReordersShortlistAndPreservesTail() async throws {
        var files: [String: String] = [:]
        for index in 0..<35 {
            let number = String(format: "%02d", index)
            files["\(number).md"] = "# Notes \(number)\n\nneedle body"
        }
        let repo = SearchTestRepository(files)
        let index = SearchTestIndex()
        let indexer = NoteSearchIndexer(repository: repo, policy: .standard, index: index)
        let reranker = TestTextReranker(mode: .reverse)
        let search = createSearchUseCases(
            repository: repo, policy: .standard, index: index, indexer: indexer, reranker: reranker)
        let hits = try await search.search("needle", limit: 35)
        #expect(hits.first?.note.path.value == "29.md")
        #expect(hits[29].note.path.value == "00.md")
        #expect(hits.suffix(5).map(\.note.path.value) == ["30.md", "31.md", "32.md", "33.md", "34.md"])
        #expect(await reranker.textCount == 30)
        #expect(hits.map(\.score) == hits.map(\.score).sorted(by: >))
    }

    @Test(arguments: [TestTextReranker.Mode.invalidLength, .nonFinite, .failure])
    func invalidOrUnavailableRerankerKeepsIndexedResults(_ mode: TestTextReranker.Mode) async throws {
        let repo = SearchTestRepository(["a.md": "# A\n\nneedle", "b.md": "# B\n\nneedle"])
        let index = SearchTestIndex()
        let indexer = NoteSearchIndexer(repository: repo, policy: .standard, index: index)
        let search = createSearchUseCases(
            repository: repo, policy: .standard, index: index, indexer: indexer,
            reranker: TestTextReranker(mode: mode))
        #expect(try await search.search("needle", limit: 2).map(\.note.path.value) == ["a.md", "b.md"])
        #expect(await repo.readCount == 2)
        #expect(await index.candidateCalls == 1)
    }

    @Test func rerankerCancellationNeverTriggersFilesystemFallback() async throws {
        let repo = SearchTestRepository(["a.md": "# A\n\nneedle", "b.md": "# B\n\nneedle"])
        let index = SearchTestIndex()
        let indexer = NoteSearchIndexer(repository: repo, policy: .standard, index: index)
        let search = createSearchUseCases(
            repository: repo, policy: .standard, index: index, indexer: indexer,
            reranker: TestTextReranker(mode: .cancelled))
        await #expect(throws: CancellationError.self) { try await search.search("needle", limit: 2) }
        #expect(await repo.readCount == 2)
    }
}

actor TestTextReranker: ITextReranker {
    enum Mode: Sendable { case reverse, invalidLength, nonFinite, failure, cancelled }
    let mode: Mode
    private(set) var textCount = 0

    init(mode: Mode) { self.mode = mode }

    func rerank(query: String, texts: [String]) throws -> [Double] {
        textCount = texts.count
        switch mode {
        case .reverse: return texts.indices.map { Double($0) }
        case .invalidLength: return []
        case .nonFinite: return texts.map { _ in .nan }
        case .failure: throw SearchTestError.unavailable
        case .cancelled: throw CancellationError()
        }
    }
}
