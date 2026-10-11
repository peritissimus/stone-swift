import Testing
import StoneDomain

struct DesktopNoteTitleExtractorTests {
    @Test func matchesDesktopHeadingAndFallbackRules() {
        #expect(DesktopNoteTitleExtractor.title(source: "front matter\n\n## Nested title\nbody") == "Nested title")
        #expect(DesktopNoteTitleExtractor.title(source: "# Title ###\ntext") == "Title ###")
        #expect(DesktopNoteTitleExtractor.title(source: "\n  First line  \nsecond") == "First line")
        #expect(DesktopNoteTitleExtractor.title(source: String(repeating: "a", count: 110)) == String(repeating: "a", count: 100))
        #expect(DesktopNoteTitleExtractor.title(source: " \n\t") == nil)
    }
}
