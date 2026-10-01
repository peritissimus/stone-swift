import StoneDomain

public func createJournalUseCases(
    repository: any INoteRepository, clock: any IClock, policy: LocationPolicy
) -> any IJournalUseCases {
    JournalUseCases(
        capture: CaptureToJournalUseCase(repository: repository, clock: clock, policy: policy),
        today: GetTodayJournalUseCase(repository: repository, clock: clock, policy: policy))
}
