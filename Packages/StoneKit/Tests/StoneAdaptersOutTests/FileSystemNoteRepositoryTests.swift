import Foundation
import Testing
import StoneDomain
@testable import StoneAdaptersOut

struct FileSystemNoteRepositoryTests {
    let root: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("stone-tests-\(UUID().uuidString)", isDirectory: true)

    @Test func writesListsAndReadsSkippingHidden() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = FileSystemNoteRepository(root: root)
        try await repo.write("# A\n\n", to: try NotePath("Work/a.md"))
        try await repo.write("# T\n\n", to: try NotePath("Personal/t.md"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".stone/templates"), withIntermediateDirectories: true)
        try Data("# hidden".utf8).write(to: root.appendingPathComponent(".stone/templates/x.md"))
        try Data("text".utf8).write(to: root.appendingPathComponent("readme.txt"))

        let listed = try await repo.listNotes().map(\.path.value).sorted()
        #expect(listed == ["Personal/t.md", "Work/a.md"])
        #expect(try await repo.read(try NotePath("Work/a.md")) == "# A\n\n")
        #expect(try await repo.info(try NotePath("Work/missing.md")) == nil)
    }

    @Test func readKeepsAByteOrderMarkSoWritesRoundTrip() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = FileSystemNoteRepository(root: root)
        let path = try NotePath("Journal/2026-10-01.md")
        try await repo.write("x", to: path)
        let file = root.appendingPathComponent("Journal/2026-10-01.md")
        let original = Data([0xEF, 0xBB, 0xBF]) + Data("# 2026-10-01\n\nhi".utf8)
        try original.write(to: file)
        try await repo.write(try await repo.read(path), to: path)
        #expect(try Data(contentsOf: file) == original)
    }

    @Test func refusesToDecodeInvalidUTF8() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = FileSystemNoteRepository(root: root)
        let path = try NotePath("Journal/2026-10-01.md")
        try await repo.write("x", to: path)
        try Data([0x23, 0x20, 0xC3, 0x28]).write(to: root.appendingPathComponent("Journal/2026-10-01.md"))
        await #expect(throws: (any Error).self) { try await repo.read(path) }
    }

    @Test func configDefaultsWhenMissing() async throws {
        let repo = AppConfigRepository(file: root.appendingPathComponent("config.json"))
        #expect(try await repo.load() == .standard)
    }

    @Test func configReadsStoneDesktopSchema() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try writeStoneConfig()
        let config = try await AppConfigRepository(file: file).load()
        #expect(config.workspacePath == "/Users/me/Notes")
        #expect(config.locationPolicy == LocationPolicy(journalFolder: "Daily"))
        #expect(config.captureShortcut == "Alt+Space")
    }

    @Test func emptyShortcutMeansDisabledNotDefault() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("config.json")
        try Data(#"{"quickCapture": {"shortcut": ""}}"#.utf8).write(to: file)
        #expect(try await AppConfigRepository(file: file).load().captureShortcut == "")
    }

    private func writeStoneConfig() throws -> URL {
        let file = root.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let json = """
            {"appearance": {"theme": "dark"}, "ai": {"enabled": true},
             "workspace": {"defaultWorkspacePath": "/Users/me/Notes", "extra": 7},
             "notes": {"locationPolicy": {"journalFolder": "Daily", "defaultNoteFolder": "Inbox",
                       "quickNoteSlotFolders": {"personal": "Inbox", "work": "Job"}}},
             "quickCapture": {"shortcut": "Alt+Space"}}
            """
        try Data(json.utf8).write(to: file)
        return file
    }

}
