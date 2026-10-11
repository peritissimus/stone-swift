import Foundation
import Testing
import StoneDomain

struct HybridSearchTests {
    @Test func exactTitleAndPhraseMatchesOutrankSemanticOnlyCandidates() throws {
        let candidates = [
            candidate("semantic.md", title: "Money", text: "financial account", semantic: 1),
            candidate("phrase.md", title: "Thoughts", text: "fix wallet leak", lexical: 1, semantic: 0.8),
            candidate("title.md", title: "Wallet leak", text: "", lexical: 4),
        ]
        let hits = HybridSearchReranker.rerank(query: "wallet leak", candidates: candidates, limit: 10)
        #expect(hits.map(\.note.path.value) == ["title.md", "phrase.md", "semantic.md"])
        #expect(hits[1].snippet.contains("wallet leak"))
    }

    @Test func keepsBestChunkAndUsesDeterministicTieBreaks() {
        let candidates = [
            candidate("b.md", title: "Notes", text: "first wallet", lexical: 2),
            candidate("a.md", title: "Notes", text: "first wallet", lexical: 2),
            candidate("b.md", title: "Notes", text: "unrelated", semantic: 0.6),
        ]
        let first = HybridSearchReranker.rerank(query: "wallet", candidates: candidates, limit: 10)
        let reversed = HybridSearchReranker.rerank(query: "wallet", candidates: candidates.reversed(), limit: 10)
        #expect(first == reversed)
        #expect(first.map(\.note.path.value) == ["a.md", "b.md"])
        #expect(first.last?.snippet == "first wallet")
        #expect(HybridSearchReranker.rerank(query: "wallet", candidates: candidates, limit: -1).isEmpty)
    }

    @Test func semanticSimilarityAndRankRerankConceptualMatches() {
        let candidates = [
            candidate("low.md", title: "Ideas", text: "day", semantic: 0.3),
            candidate("high.md", title: "Ideas", text: "night", semantic: 0.9),
            candidate("invalid.md", title: "Ideas", text: "void", semantic: .nan),
        ]
        #expect(HybridSearchReranker.rerank(query: "sleep", candidates: candidates, limit: 1).first?.note.path.value == "high.md")
    }

    private func candidate(
        _ path: String, title: String, text: String, lexical: Int? = nil, semantic: Double? = nil
    ) -> SearchCandidate {
        SearchCandidate(
            note: NoteSummary(path: try! NotePath(path), title: title, modifiedAt: Date(timeIntervalSince1970: 1), isJournal: false),
            text: text, lexicalRank: lexical, semanticSimilarity: semantic)
    }
}
