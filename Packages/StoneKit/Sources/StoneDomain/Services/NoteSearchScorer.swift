import Foundation

/// Ranks a note against a free-text query; every term must appear in the title or body.
public enum NoteSearchScorer {
    public static let snippetLength = 240

    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    public static func terms(of query: String) -> [String] {
        query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    public static func score(query: String, title: String, body: String) -> (score: Double, snippet: String)? {
        let words = terms(of: query)
        guard !words.isEmpty else { return nil }
        var score = 0.0
        var firstBodyHit: Range<String.Index>?
        for word in words {
            let inTitle = title.range(of: word, options: options)
            let inBody = body.range(of: word, options: options)
            guard inTitle != nil || inBody != nil else { return nil }
            if let inTitle { score += inTitle.lowerBound == title.startIndex ? 5 : 3 }
            if let inBody {
                score += min(Double(occurrences(of: word, in: body)), 5) * 0.5
                if firstBodyHit.map({ inBody.lowerBound < $0.lowerBound }) ?? true { firstBodyHit = inBody }
            }
        }
        if words.count > 1, title.range(of: query, options: options) != nil { score += 5 }
        return (score, snippet(of: body, around: firstBodyHit))
    }

    static func occurrences(of word: String, in text: String) -> Int {
        var count = 0
        var searchStart = text.startIndex
        while count < 5, let hit = text.range(of: word, options: options, range: searchStart..<text.endIndex) {
            count += 1
            searchStart = hit.upperBound
        }
        return count
    }

    static func snippet(of body: String, around hit: Range<String.Index>?) -> String {
        let lead = 60
        let start = hit.map { body.index($0.lowerBound, offsetBy: -lead, limitedBy: body.startIndex) ?? body.startIndex }
            ?? body.startIndex
        let end = body.index(start, offsetBy: snippetLength, limitedBy: body.endIndex) ?? body.endIndex
        let flattened = body[start..<end]
            .split(whereSeparator: { $0.isNewline })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return (start > body.startIndex ? "…" : "") + flattened + (end < body.endIndex ? "…" : "")
    }
}
