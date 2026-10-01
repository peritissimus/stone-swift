import StoneDomain

public final class ListNotesUseCase: Sendable {
    private let repository: any INoteRepository
    private let policy: LocationPolicy

    public init(repository: any INoteRepository, policy: LocationPolicy) {
        self.repository = repository
        self.policy = policy
    }

    public func execute() async throws -> [NoteSummary] {
        try await loadAllNotes(from: repository, policy: policy).map(\.summary)
    }
}
