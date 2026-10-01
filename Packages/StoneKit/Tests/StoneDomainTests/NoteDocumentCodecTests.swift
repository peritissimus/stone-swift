import Testing
@testable import StoneDomain

struct NoteDocumentCodecTests {
    @Test func splitsH1TitleFromBody() {
        let parts = NoteDocumentCodec.split("# Plan\n\nfirst line\nsecond")
        #expect(parts.title == "Plan")
        #expect(parts.body == "first line\nsecond")
    }

    @Test func sourceWithoutH1IsAllBody() {
        let parts = NoteDocumentCodec.split("## Sub\ntext")
        #expect(parts.title == nil)
        #expect(parts.body == "## Sub\ntext")
    }

    @Test func composeRoundTrips() {
        let source = NoteDocumentCodec.compose(title: "Plan", body: "body")
        #expect(source == "# Plan\n\nbody")
        #expect(NoteDocumentCodec.split(source).title == "Plan")
    }
}

struct NotePathTests {
    @Test func acceptsNestedMarkdown() throws {
        let path = try NotePath("Work/Projects/20260101-000000-001.md")
        #expect(path.stem == "20260101-000000-001")
        #expect(path.folder.value == "Work/Projects")
    }

    @Test(arguments: ["../x.md", ".stone/t.md", "a/.hidden.md", "notes.txt", ".md", "a//b.md"])
    func rejectsUnsafeOrNonMarkdown(_ raw: String) {
        #expect(throws: NoteError.self) { try NotePath(raw) }
    }
}

struct NoteEntityTests {
    @Test func journalTitleIsItsDate() throws {
        let note = NoteEntity(
            path: try NotePath("Journal/2026-09-29.md"), source: "# whatever\n\nx", modifiedAt: .distantPast,
            policy: .standard)
        #expect(note.isJournal)
        #expect(note.title == "2026-09-29")
    }

    @Test func byteOrderMarkDoesNotHideTheTitle() {
        #expect(NoteDocumentCodec.split("\u{FEFF}# Plan\n\nbody").title == "Plan")
    }

    @Test func crlfTitleHasNoCarriageReturn() {
        #expect(NoteDocumentCodec.split("# Plan\r\n\r\nbody").title == "Plan")
    }

    @Test func noteWithoutH1FallsBackToFileStem() throws {
        let note = NoteEntity(
            path: try NotePath("Personal/ideas.md"), source: "just text", modifiedAt: .distantPast,
            policy: .standard)
        #expect(note.title == "ideas")
        #expect(note.body == "just text")
    }
}
