/// Journal files are named by their day, which is also their title.
public enum NoteFileNaming {
    public static func journalFileName(for date: JournalDate) -> String {
        "\(date)\(NotePath.fileExtension)"
    }
}
