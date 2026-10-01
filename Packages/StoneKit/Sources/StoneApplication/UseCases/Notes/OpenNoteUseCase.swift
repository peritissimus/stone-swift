import StoneDomain

public final class OpenNoteUseCase: Sendable {
    private let repository: any INoteRepository
    private let policy: LocationPolicy

    public init(repository: any INoteRepository, policy: LocationPolicy) {
        self.repository = repository
        self.policy = policy
    }

    public func execute(_ path: NotePath) async throws -> NoteEntity {
        try await loadNote(path, from: repository, policy: policy)
    }
}
