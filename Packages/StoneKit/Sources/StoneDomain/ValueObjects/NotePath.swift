/// A note's location relative to the workspace root: a visible `.md` file.
public struct NotePath: Hashable, Sendable, Comparable, CustomStringConvertible {
    public static let fileExtension = ".md"

    public let value: String

    public init(_ raw: String) throws {
        let parts = raw.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard raw.lowercased().hasSuffix(NotePath.fileExtension),
            parts.allSatisfy(FolderPath.isVisibleComponent),
            let last = parts.last, last.count > NotePath.fileExtension.count
        else { throw NoteError.invalidPath(raw) }
        value = raw
    }

    public init(folder: FolderPath, fileName: String) throws {
        try self.init(folder.isRoot ? fileName : "\(folder.value)/\(fileName)")
    }

    public var fileName: String { value.split(separator: "/").last.map(String.init) ?? value }
    public var stem: String { String(fileName.dropLast(NotePath.fileExtension.count)) }
    public var description: String { value }

    public var folder: FolderPath {
        let parts = value.split(separator: "/").dropLast()
        return (try? FolderPath(parts.joined(separator: "/"))) ?? .root
    }

    public static func < (lhs: NotePath, rhs: NotePath) -> Bool { lhs.value < rhs.value }
}
