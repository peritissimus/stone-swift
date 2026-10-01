/// Read-only access to previous notes. This app takes notes; it never edits one.
public protocol INoteUseCases: Sendable {
    /// Most recently modified first.
    func listNotes() async throws -> [NoteSummary]
    func openNote(_ path: NotePath) async throws -> NoteEntity
    var workspaceLocation: String { get }
}
