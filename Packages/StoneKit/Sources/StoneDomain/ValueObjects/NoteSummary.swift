import Foundation

/// A note as lists show it: identity, resolved title and recency.
public struct NoteSummary: Hashable, Sendable, Identifiable {
    public let path: NotePath
    public let title: String
    public let modifiedAt: Date
    public let isJournal: Bool

    public var id: NotePath { path }

    public init(path: NotePath, title: String, modifiedAt: Date, isJournal: Bool) {
        self.path = path
        self.title = title
        self.modifiedAt = modifiedAt
        self.isJournal = isJournal
    }
}
