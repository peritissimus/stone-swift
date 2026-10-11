import Testing
import StoneDomain

struct DesktopNoteChunkerTests {
    @Test func matchesDesktopChunkFingerprintsAndTokenCounts() {
        // Signatures generated with Stone desktop's NoteChunker.ts and hashText.ts.
        let cases: [(String, [String])] = [
            ("---\ntags: [work]\n---\n# Main\n\nfirst\n\n## Child\nsecond\n\n```swift\n# code\n```\n\n# Next\nlast", [
                "Main|89d7ed7f996f1d41|2", "Main/Child|3102f202d2a26020|7", "Next|0456d2ad905847d9|1",
            ]),
            ("# Main\n\n" + String(repeating: "Long sentence about cafés and stones 🪨. ", count: 160) + "\n\nlast needle", [
                "Main|9789a4adc1c7278e|441", "Main|3974f9579c5ca54f|486",
                "Main|3974f9579c5ca54f|486", "Main|085ca08f3c2c1aa3|412",
            ]),
            ("# Emoji\n\n" + String(repeating: "🪨a", count: 1_600), [
                "Emoji|f1935b8cf4520045|450", "Emoji|a27effad11ead4cd|496", "Emoji|cb6a357d0940c9ed|346",
            ]),
            ("# Plan\n\n" + String(repeating: "A", count: 1_100) + "\n\n" + String(repeating: "B", count: 900) + "\n\nend", [
                "Plan|cca196eeff43d581|275", "Plan|dfc8f0a97188dafe|272",
            ]),
            ("---\r\ntags: [daily]\r\n---\r\n# Title\r\n\r\nbody", ["|f75b12c8c92d671b|6", "Title|cd4de79bc6c93295|1"]),
            ("# Title\n\n## Subheading\n", []),
        ]
        for (source, expected) in cases {
            let actual = DesktopNoteChunker.chunks(source: source).map {
                $0.headingPath.joined(separator: "/") + "|" + NoteContentHasher.hash($0.text) + "|" + String($0.tokenCount)
            }
            #expect(actual == expected)
        }
    }
}
