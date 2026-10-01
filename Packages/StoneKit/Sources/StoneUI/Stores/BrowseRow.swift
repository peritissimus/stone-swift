import StoneDomain

/// A previous note in the ⌥O list, with the excerpt a search matched.
struct BrowseRow: Identifiable, Hashable {
    let note: NoteSummary
    let snippet: String?

    var id: NotePath { note.path }
}
