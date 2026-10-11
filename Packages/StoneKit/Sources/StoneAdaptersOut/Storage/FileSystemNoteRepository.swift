import Foundation
import StoneDomain

/// Notes as plain `.md` files under one workspace folder — the same folder Stone desktop uses.
public final class FileSystemNoteRepository: INoteRepository {
    private let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    public var locationDescription: String { root.path }

    public func listNotes() async throws -> [NoteFileInfo] {
        try walkNotes()
    }

    /// Synchronous: `DirectoryEnumerator` cannot be iterated from an async context.
    private func walkNotes() throws -> [NoteFileInfo] {
        guard try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw CocoaError(.fileReadUnknown)
        }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]
        var enumerationError: (any Error)?
        guard
            let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, error in enumerationError = error; return false })
        else { throw CocoaError(.fileReadUnknown) }
        var notes: [NoteFileInfo] = []
        for case let url as URL in walker {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                let path = try? NotePath(relativePath(of: url))
            else { continue }
            notes.append(NoteFileInfo(path: path, modifiedAt: values.contentModificationDate ?? .distantPast))
        }
        // Never publish a partial inventory: reconciliation interprets omissions as deletions.
        if let enumerationError { throw enumerationError }
        return notes
    }

    /// Decodes without dropping a leading BOM, so an append writes the file's bytes back unchanged.
    public func read(_ path: NotePath) async throws -> String {
        let data = try Data(contentsOf: url(for: path))
        guard String(data: data, encoding: .utf8) != nil else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        return String(decoding: data, as: UTF8.self)
    }

    public func info(_ path: NotePath) async throws -> NoteFileInfo? {
        do {
            let values = try url(for: path).resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values.isRegularFile == true else { return nil }
            return NoteFileInfo(path: path, modifiedAt: values.contentModificationDate ?? .distantPast)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        }
    }

    public func write(_ source: String, to path: NotePath) async throws {
        let target = url(for: path)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(source.utf8).write(to: target, options: .atomic)
    }

    private func url(for path: NotePath) -> URL {
        path.value.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
    }

    private func relativePath(of url: URL) -> String {
        let full = url.standardizedFileURL.path
        let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return full.hasPrefix(base) ? String(full.dropFirst(base.count)) : full
    }
}
