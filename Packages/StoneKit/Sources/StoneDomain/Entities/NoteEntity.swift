import Foundation

/// A note as read from disk: identity is its path; the title is its H1 (journals: their date).
public struct NoteEntity: Hashable, Sendable, Identifiable {
    public let path: NotePath
    public let title: String
    public let body: String
    public let isJournal: Bool
    public let modifiedAt: Date

    public var id: NotePath { path }

    public init(path: NotePath, source: String, modifiedAt: Date, policy: LocationPolicy) {
        let parts = NoteDocumentCodec.split(source)
        self.path = path
        self.isJournal = policy.isJournal(path)
        self.title = isJournal ? path.stem : (parts.title ?? path.stem)
        self.body = parts.title == nil ? source : parts.body
        self.modifiedAt = modifiedAt
    }

    public var summary: NoteSummary {
        NoteSummary(path: path, title: title, modifiedAt: modifiedAt, isJournal: isJournal)
    }
}
