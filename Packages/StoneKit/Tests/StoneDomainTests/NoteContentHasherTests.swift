import Foundation
import Testing
import StoneDomain

struct NoteContentHasherTests {
    @Test func fingerprintsMatchDesktopIncludingUnicodeAndExactLineEndings() {
        // Expected values produced by stone/src/main/domain/services/hashText.ts.
        #expect(NoteContentHasher.hash("") == "0000000000000000")
        #expect(NoteContentHasher.hash("hello") == "a430d84680aabd0b")
        #expect(NoteContentHasher.hash("# Journal\r\n\r\ncafé 🪨 नमस्ते") == "869d722ea156b2ec")
        let source = "---\ntags: [daily]\n---\n# A\n\ntext"
        #expect(NoteContentHasher.hash(source) == "0f145fb1d63dfd44")
        let note = NoteEntity(path: try! NotePath("a.md"), source: source, modifiedAt: .distantPast, policy: .standard)
        #expect(note.source == source)
    }
}
