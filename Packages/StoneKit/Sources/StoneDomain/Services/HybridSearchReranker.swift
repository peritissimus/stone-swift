import Foundation

/// Query-time reranking blends lexical and semantic evidence, with exact matches protected.
public enum HybridSearchReranker {
    public static func rerank(query: String, candidates: [SearchCandidate], limit: Int) -> [SearchHit] {
        let terms = NoteSearchScorer.terms(of: query)
        guard limit > 0, !terms.isEmpty else { return [] }
        let phrase = terms.joined(separator: " ")
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let semanticOrder = candidates.indices.filter {
            candidates[$0].semanticSimilarity?.isFinite == true
        }.sorted {
            let left = candidates[$0].semanticSimilarity ?? 0
            let right = candidates[$1].semanticSimilarity ?? 0
            if left != right { return left > right }
            if candidates[$0].note.path != candidates[$1].note.path {
                return candidates[$0].note.path < candidates[$1].note.path
            }
            return candidates[$0].text < candidates[$1].text
        }
        let semanticRanks = Dictionary(uniqueKeysWithValues: semanticOrder.enumerated().map { ($1, $0 + 1) })
        var best: [NotePath: SearchHit] = [:]
        for (offset, candidate) in candidates.enumerated() {
            let lexical = NoteSearchScorer.score(query: phrase, title: candidate.note.title, body: candidate.text)
            let titlePhrase = candidate.note.title.range(of: phrase, options: options) != nil
            let textPhrase = candidate.text.range(of: phrase, options: options) != nil
            let similarity = candidate.semanticSimilarity.flatMap { $0.isFinite ? max(0, min(1, $0)) : nil } ?? 0
            guard lexical != nil || candidate.lexicalRank != nil || similarity > 0 else { continue }
            var score = titlePhrase ? 100.0 : (textPhrase ? 60.0 : (lexical != nil ? 40.0 : 0.0))
            score += min(lexical?.score ?? 0, 15)
            if let rank = candidate.lexicalRank { score += 60 / (60 + Double(max(1, rank))) }
            if let rank = semanticRanks[offset] { score += 60 / (60 + Double(rank)) }
            score += similarity * 3
            let firstHit = terms.compactMap { candidate.text.range(of: $0, options: options) }
                .min { $0.lowerBound < $1.lowerBound }
            let hit = SearchHit(
                note: candidate.note,
                snippet: lexical?.snippet ?? NoteSearchScorer.snippet(of: candidate.text, around: firstHit),
                score: score)
            if let previous = best[hit.note.path],
               previous.score > hit.score || (previous.score == hit.score && previous.snippet <= hit.snippet) {
                continue
            }
            best[hit.note.path] = hit
        }
        return Array(best.values.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.note.modifiedAt != $1.note.modifiedAt { return $0.note.modifiedAt > $1.note.modifiedAt }
            return $0.note.path < $1.note.path
        }.prefix(limit))
    }
}
