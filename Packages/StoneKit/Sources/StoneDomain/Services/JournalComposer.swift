import Foundation

/// How a daily note starts and how captures accumulate in it.
public enum JournalComposer {
    public static func seed(for date: JournalDate) -> String {
        NoteDocumentCodec.compose(title: date.description, body: "")
    }

    /// Appends `[HH:MM] text` as its own paragraph; blank captures change nothing.
    public static func append(_ text: String, at time: ClockTime, to source: String) -> String {
        let entry = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entry.isEmpty else { return source }
        var base = source
        while let last = base.last, last.isWhitespace { base.removeLast() }
        return base + "\n\n\(time.stamp) \(entry)"
    }
}
