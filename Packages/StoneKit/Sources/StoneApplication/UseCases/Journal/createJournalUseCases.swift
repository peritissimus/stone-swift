import StoneDomain

public func createJournalUseCases(
    repository: any INoteRepository, clock: any IClock, policy: LocationPolicy,
    indexer: NoteSearchIndexer? = nil
) -> any IJournalUseCases {
    JournalUseCases(
        capture: CaptureToJournalUseCase(repository: repository, clock: clock, policy: policy, indexer: indexer),
        today: GetTodayJournalUseCase(repository: repository, clock: clock, policy: policy))
}
