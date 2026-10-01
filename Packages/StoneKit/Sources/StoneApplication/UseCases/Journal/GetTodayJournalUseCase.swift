import StoneDomain

/// Reads today's journal without creating it, for the read-only Today view.
public final class GetTodayJournalUseCase: Sendable {
    private let repository: any INoteRepository
    private let clock: any IClock
    private let policy: LocationPolicy

    public init(repository: any INoteRepository, clock: any IClock, policy: LocationPolicy) {
        self.repository = repository
        self.clock = clock
        self.policy = policy
    }

    public func execute() async throws -> NoteEntity? {
        let path = try policy.journalPath(for: JournalDate(date: clock.now, calendar: clock.calendar))
        guard try await repository.info(path) != nil else { return nil }
        return try await loadNote(path, from: repository, policy: policy)
    }
}
