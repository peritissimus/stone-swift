/// Where daily notes live inside a workspace — Stone's `notes.locationPolicy.journalFolder`.
public struct LocationPolicy: Hashable, Sendable {
    public var journalFolder: String

    public static let standard = LocationPolicy(journalFolder: "Journal")

    public init(journalFolder: String) {
        self.journalFolder = journalFolder
    }

    public func journalPath(for date: JournalDate) throws -> NotePath {
        try NotePath(folder: FolderPath(journalFolder), fileName: NoteFileNaming.journalFileName(for: date))
    }

    public func isJournal(_ path: NotePath) -> Bool {
        (try? FolderPath(journalFolder)) == path.folder && JournalDate(parsing: path.stem) != nil
    }
}
