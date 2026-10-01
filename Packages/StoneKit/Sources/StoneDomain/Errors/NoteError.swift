/// Business-rule violations around notes and their locations.
public enum NoteError: Error, Equatable, Sendable {
    case invalidPath(String)
    case invalidFolder(String)
    case notFound(NotePath)
}
