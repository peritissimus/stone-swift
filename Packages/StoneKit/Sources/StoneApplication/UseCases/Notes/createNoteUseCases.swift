import StoneDomain

public func createNoteUseCases(repository: any INoteRepository, policy: LocationPolicy) -> any INoteUseCases {
    NoteUseCases(
        list: ListNotesUseCase(repository: repository, policy: policy),
        open: OpenNoteUseCase(repository: repository, policy: policy),
        workspaceLocation: repository.locationDescription)
}
