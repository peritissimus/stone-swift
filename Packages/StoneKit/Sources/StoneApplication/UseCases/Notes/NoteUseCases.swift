import StoneDomain

/// The read-only notes facade driving adapters depend on.
public final class NoteUseCases: INoteUseCases {
    private let list: ListNotesUseCase
    private let open: OpenNoteUseCase
    public let workspaceLocation: String

    init(list: ListNotesUseCase, open: OpenNoteUseCase, workspaceLocation: String) {
        self.list = list
        self.open = open
        self.workspaceLocation = workspaceLocation
    }

    public func listNotes() async throws -> [NoteSummary] { try await list.execute() }
    public func openNote(_ path: NotePath) async throws -> NoteEntity { try await open.execute(path) }
}
