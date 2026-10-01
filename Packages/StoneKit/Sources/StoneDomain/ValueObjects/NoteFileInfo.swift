import Foundation

/// What storage knows about a note file without reading it.
public struct NoteFileInfo: Hashable, Sendable {
    public let path: NotePath
    public let modifiedAt: Date

    public init(path: NotePath, modifiedAt: Date) {
        self.path = path
        self.modifiedAt = modifiedAt
    }
}
