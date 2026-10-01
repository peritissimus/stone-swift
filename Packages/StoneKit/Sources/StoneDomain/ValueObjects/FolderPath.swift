/// A folder relative to the workspace root; the root itself is the empty path.
public struct FolderPath: Hashable, Sendable, Comparable, CustomStringConvertible {
    public static let root = FolderPath(components: [])

    public let components: [String]

    public init(_ raw: String) throws {
        let parts = raw.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.allSatisfy(FolderPath.isVisibleComponent) else { throw NoteError.invalidFolder(raw) }
        components = parts
    }

    private init(components: [String]) {
        self.components = components
    }

    public var value: String { components.joined(separator: "/") }
    public var name: String { components.last ?? "" }
    public var isRoot: Bool { components.isEmpty }
    public var description: String { value }

    public func appending(_ component: String) throws -> FolderPath {
        try FolderPath((components + [component]).joined(separator: "/"))
    }

    public static func < (lhs: FolderPath, rhs: FolderPath) -> Bool { lhs.value < rhs.value }

    /// Hidden (`.stone`, `.git`) and parent references never name a workspace folder.
    static func isVisibleComponent(_ part: String) -> Bool {
        !part.isEmpty && !part.hasPrefix(".") && part != ".."
    }
}
