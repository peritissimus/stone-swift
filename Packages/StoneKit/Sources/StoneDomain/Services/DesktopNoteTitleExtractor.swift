import Foundation

/// Mirrors desktop MarkdownProcessor's first-heading, then first-nonempty-line title rule.
public enum DesktopNoteTitleExtractor {
    public static func title(source: String) -> String? {
        let trimSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))
        let lines = source.components(separatedBy: "\n")
        let heading = try! NSRegularExpression(pattern: "^#{1,6}\\s{1,10}(.{1,500})$")
        for line in lines {
            let text = line as NSString
            if let match = heading.firstMatch(in: line, range: NSRange(location: 0, length: text.length)),
               match.range(at: 1).length <= 500 {
                return text.substring(with: match.range(at: 1)).trimmingCharacters(in: trimSet)
            }
        }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: trimSet)
            if !trimmed.isEmpty { return String(decoding: trimmed.utf16.prefix(100), as: UTF16.self) }
        }
        return nil
    }
}
