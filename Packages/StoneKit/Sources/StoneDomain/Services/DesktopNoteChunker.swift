import Foundation

/// Matches Stone desktop's heading-aware 1,800 UTF-16-unit chunks and 180-unit overlap.
public enum DesktopNoteChunker {
    private static let maxChars = 1_800
    private static let overlap = 180
    private static let trimSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))

    public static func chunks(source: String) -> [DesktopNoteChunk] {
        var markdown = source
        if markdown.hasPrefix("---\n"), let end = markdown.range(of: "\n---", range: markdown.index(markdown.startIndex, offsetBy: 4)..<markdown.endIndex) {
            markdown = String(markdown[end.upperBound...]).replacingOccurrences(of: "^\\n+", with: "", options: .regularExpression)
        }
        markdown = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        guard !trim(markdown).isEmpty else { return [] }
        var sections: [(headings: [String], lines: [String])] = []
        var headings: [(level: Int, text: String)] = []
        var lines: [String] = []
        var fence: String?
        let heading = try! NSRegularExpression(pattern: "^(#{1,6})\\s+(.+?)\\s*#*\\s*$")
        for line in markdown.components(separatedBy: "\n") {
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                let marker = String(line.prefix(3))
                if fence == nil { fence = marker }
                else if fence == marker { fence = nil }
                lines.append(line)
                continue
            }
            let nsLine = line as NSString
            if fence == nil, let match = heading.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) {
                if lines.contains(where: { !trim($0).isEmpty }) { sections.append((headings.map(\.text), lines)) }
                let level = match.range(at: 1).length
                while let last = headings.last, last.level >= level { headings.removeLast() }
                headings.append((level, trim(nsLine.substring(with: match.range(at: 2)))))
                lines = []
            } else {
                lines.append(line)
            }
        }
        if lines.contains(where: { !trim($0).isEmpty }) { sections.append((headings.map(\.text), lines)) }
        var result: [DesktopNoteChunk] = []
        for section in sections {
            let text = trim(section.lines.joined(separator: "\n"))
            let paragraphs = split(text, pattern: "\\n{2,}").map(trim).filter { !$0.isEmpty }
            result += pack(paragraphs).map { DesktopNoteChunk(text: $0, headingPath: section.headings) }
        }
        if result.count >= 2 {
            let last = result[result.count - 1], previous = result[result.count - 2]
            if last.text.utf16.count < 200,
               last.headingPath.joined(separator: "|") == previous.headingPath.joined(separator: "|"),
               previous.text.utf16.count + last.text.utf16.count + 2 <= maxChars {
                result.removeLast(2)
                result.append(DesktopNoteChunk(text: previous.text + "\n\n" + last.text, headingPath: previous.headingPath))
            }
        }
        return result
    }

    private static func pack(_ paragraphs: [String]) -> [String] {
        var packed: [String] = []
        var buffer = ""
        for paragraph in paragraphs {
            if paragraph.utf16.count > maxChars {
                if !trim(buffer).isEmpty { packed.append(trim(buffer)) }
                buffer = ""
                packed += splitOversized(paragraph)
            } else {
                let candidate = buffer.isEmpty ? paragraph : buffer + "\n\n" + paragraph
                if candidate.utf16.count <= maxChars { buffer = candidate }
                else {
                    if !trim(buffer).isEmpty { packed.append(trim(buffer)) }
                    buffer = paragraph
                }
            }
        }
        if !trim(buffer).isEmpty { packed.append(trim(buffer)) }
        return packed.enumerated().map { index, text in
            guard index > 0 else { return text }
            let previous = Array(packed[index - 1].utf16)
            return String(decoding: previous.suffix(overlap), as: UTF16.self) + "\n" + text
        }
    }

    private static func splitOversized(_ paragraph: String) -> [String] {
        let sentences = split(paragraph, pattern: #"(?<=[.!?])\s+(?=[A-Z(\[])"#).map(trim).filter { !$0.isEmpty }
        var result: [String] = []
        var buffer = ""
        for sentence in sentences {
            if sentence.utf16.count > maxChars {
                if !buffer.isEmpty { result.append(trim(buffer)); buffer = "" }
                let units = Array(sentence.utf16)
                for start in stride(from: 0, to: units.count, by: maxChars) {
                    result.append(String(decoding: units[start..<min(start + maxChars, units.count)], as: UTF16.self))
                }
            } else {
                let candidate = buffer.isEmpty ? sentence : buffer + " " + sentence
                if candidate.utf16.count <= maxChars { buffer = candidate }
                else { result.append(trim(buffer)); buffer = sentence }
            }
        }
        if !trim(buffer).isEmpty { result.append(trim(buffer)) }
        return result
    }

    private static func trim(_ text: String) -> String { text.trimmingCharacters(in: trimSet) }

    private static func split(_ text: String, pattern: String) -> [String] {
        let source = text as NSString
        let regex = try! NSRegularExpression(pattern: pattern)
        var result: [String] = []
        var offset = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result.append(source.substring(with: NSRange(location: offset, length: match.range.location - offset)))
            offset = NSMaxRange(match.range)
        }
        result.append(source.substring(from: offset))
        return result
    }
}
