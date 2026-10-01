import StoneDomain

public func createSearchUseCases(repository: any INoteRepository, policy: LocationPolicy) -> any ISearchUseCases {
    SearchUseCases(searchNotes: SearchNotesUseCase(repository: repository, policy: policy))
}
