import StoneDomain

/// The in-ports this driving adapter may call — facades only, never a use case or an out-port.
public struct StoneServices: Sendable {
    public let journal: any IJournalUseCases
    public let notes: any INoteUseCases
    public let search: any ISearchUseCases

    public init(journal: any IJournalUseCases, notes: any INoteUseCases, search: any ISearchUseCases) {
        self.journal = journal
        self.notes = notes
        self.search = search
    }
}
