import Foundation

/// Stone's on-disk note shape: `# Title`, a blank line, then the body.
public enum NoteDocumentCodec {
    /// The title is the first line only when that line is an H1; otherwise the whole source is body.
    public static func split(_ source: String) -> (title: String?, body: String) {
        // `\r\n` is one Character, so newline tests use `isNewline`, never `== "\n"`.
        let trimmedStart = source.drop(while: { $0.isNewline || $0 == "\u{FEFF}" })
        guard trimmedStart.hasPrefix("# ") else { return (nil, source) }
        let lineEnd = trimmedStart.firstIndex(where: \.isNewline) ?? trimmedStart.endIndex
        let title = trimmedStart[trimmedStart.index(trimmedStart.startIndex, offsetBy: 2)..<lineEnd]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmedStart[lineEnd...].drop(while: \.isNewline)
        return (title.isEmpty ? nil : title, String(body))
    }

    public static func compose(title: String, body: String) -> String {
        "# \(title)\n\n\(body)"
    }
}
