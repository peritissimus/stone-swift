/// What the app needs from note storage. Paths are workspace-relative; the adapter owns the root.
public protocol INoteRepository: Sendable {
    func listNotes() async throws -> [NoteFileInfo]
    func read(_ path: NotePath) async throws -> String
    func info(_ path: NotePath) async throws -> NoteFileInfo?
    /// Creates intermediate folders; replaces any existing file.
    func write(_ source: String, to path: NotePath) async throws
    /// A path the user can open in Finder; presentation only, never parsed by the app.
    var locationDescription: String { get }
}
