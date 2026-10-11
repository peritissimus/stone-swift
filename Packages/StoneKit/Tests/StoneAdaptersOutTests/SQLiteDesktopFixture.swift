import Foundation
import StoneDomain
@testable import StoneAdaptersOut

/// A disposable fixture of the desktop schema, never the user's database.
struct SQLiteDesktopFixture {
    static let model = "Xenova/bge-small-en-v1.5"
    let root: URL
    let workspaceURL: URL
    let otherWorkspaceURL: URL
    let databaseURL: URL
    let connection: SQLiteConnection

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("stone-desktop-db-tests-\(UUID().uuidString)")
        workspaceURL = root.appendingPathComponent("workspace")
        otherWorkspaceURL = root.appendingPathComponent("other-workspace")
        databaseURL = root.appendingPathComponent("stone.db")
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherWorkspaceURL, withIntermediateDirectories: true)
        try Data().write(to: databaseURL)
        connection = try SQLiteConnection(databaseURL: databaseURL)
        try connection.execute("""
            PRAGMA foreign_keys = ON;
            PRAGMA user_version = 73;
            CREATE TABLE workspaces(id TEXT PRIMARY KEY, name TEXT NOT NULL, folder_path TEXT NOT NULL UNIQUE,
                is_active INTEGER DEFAULT 0, created_at INTEGER NOT NULL, last_accessed_at INTEGER NOT NULL);
            CREATE TABLE notebooks(id TEXT PRIMARY KEY, name TEXT NOT NULL);
            CREATE TABLE notes(id TEXT PRIMARY KEY, title TEXT DEFAULT 'Untitled', file_path TEXT,
                notebook_id TEXT REFERENCES notebooks(id), workspace_id TEXT REFERENCES workspaces(id) ON DELETE CASCADE,
                is_favorite INTEGER DEFAULT 0, is_pinned INTEGER DEFAULT 0, is_archived INTEGER DEFAULT 0,
                is_deleted INTEGER DEFAULT 0, deleted_at INTEGER, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
            CREATE TABLE note_chunks(id TEXT PRIMARY KEY NOT NULL, note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
                workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE, chunk_index INTEGER NOT NULL,
                heading_path TEXT NOT NULL DEFAULT '[]', text TEXT NOT NULL, content_hash TEXT NOT NULL,
                token_count INTEGER NOT NULL DEFAULT 0, embedding BLOB, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
            CREATE TABLE note_index_records(note_id TEXT PRIMARY KEY REFERENCES notes(id) ON DELETE CASCADE,
                workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE, content_hash TEXT NOT NULL,
                chunk_count INTEGER NOT NULL DEFAULT 0, indexed_at INTEGER, model TEXT, dimensions INTEGER,
                status TEXT NOT NULL DEFAULT 'pending', error TEXT);
            CREATE VIRTUAL TABLE note_chunks_fts USING fts5(chunk_id UNINDEXED, note_id UNINDEXED, workspace_id UNINDEXED,
                title, heading_path, text, tokenize='porter unicode61');
            CREATE TABLE note_tags(note_id TEXT REFERENCES notes(id), tag_id TEXT, created_at INTEGER);
            CREATE TABLE note_topics(note_id TEXT REFERENCES notes(id), topic_id TEXT, confidence REAL, is_manual INTEGER);
            CREATE TABLE __drizzle_migrations(id INTEGER PRIMARY KEY, hash TEXT NOT NULL, created_at INTEGER);
            INSERT INTO __drizzle_migrations VALUES (1, 'desktop-migration', 123);
            INSERT INTO notebooks VALUES ('book', 'Preserved notebook');
            """)
        let insert = try connection.prepare("INSERT INTO workspaces VALUES (?, ?, ?, 0, 1, 1)")
        for (id, url) in [("main", workspaceURL), ("other", otherWorkspaceURL)] {
            try insert.bind(id, at: 1)
            try insert.bind(id, at: 2)
            try insert.bind(url.standardizedFileURL.resolvingSymlinksInPath().path, at: 3)
            _ = try insert.step()
            try insert.reset()
        }
    }

    func index() throws -> SQLiteNoteSearchIndex {
        try SQLiteNoteSearchIndex(databaseURL: databaseURL, workspaceURL: workspaceURL)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    func note(_ path: String = "note.md", source: String = "# Orchard\n\nApple trees blossom.", time: Double = 88.125) throws -> NoteEntity {
        NoteEntity(path: try NotePath(path), source: source, modifiedAt: Date(timeIntervalSince1970: time), policy: .standard)
    }

    func seed(id: String = "existing", path: String = "note.md", source: String = "# Orchard\n\nApple trees blossom.",
              workspace: String = "main", title: String = "Desktop title", deleted: Bool = false,
              vector: [Double]? = nil, model: String = SQLiteDesktopFixture.model) throws {
        let insert = try connection.prepare("""
            INSERT INTO notes(id, title, file_path, notebook_id, workspace_id, is_favorite, is_pinned, is_archived,
                is_deleted, deleted_at, created_at, updated_at) VALUES (?, ?, ?, 'book', ?, 1, 1, 1, ?, 17, 10, 20)
            """)
        try insert.bind(id, at: 1); try insert.bind(title, at: 2); try insert.bind(path, at: 3)
        try insert.bind(workspace, at: 4); try insert.bind(deleted ? Int64(1) : Int64(0), at: 5)
        _ = try insert.step()
        let chunk = try connection.prepare("""
            INSERT INTO note_chunks(id, note_id, workspace_id, chunk_index, heading_path, text, content_hash,
                token_count, embedding, created_at, updated_at) VALUES (?, ?, ?, 0, '["Section"]', ?, ?, 10, ?, 10, 20)
            """)
        try chunk.bind(id + ":0", at: 1); try chunk.bind(id, at: 2); try chunk.bind(workspace, at: 3)
        try chunk.bind(source, at: 4); try chunk.bind(NoteContentHasher.hash(source), at: 5)
        if let vector { try chunk.bind(blob(vector), at: 6) }
        _ = try chunk.step()
        let fts = try connection.prepare("INSERT INTO note_chunks_fts VALUES (?, ?, ?, ?, 'Section', ?)")
        try fts.bind(id + ":0", at: 1); try fts.bind(id, at: 2); try fts.bind(workspace, at: 3)
        try fts.bind(title, at: 4); try fts.bind(source, at: 5); _ = try fts.step()
        let record = try connection.prepare("""
            INSERT INTO note_index_records VALUES (?, ?, ?, 1, 20, ?, 384, ?, NULL)
            """)
        try record.bind(id, at: 1); try record.bind(workspace, at: 2); try record.bind(NoteContentHasher.hash(source), at: 3)
        try record.bind(model, at: 4); try record.bind(vector == nil ? "pending" : "indexed", at: 5); _ = try record.step()
        let tags = try connection.prepare("INSERT INTO note_tags VALUES (?, 'tag', 1)")
        try tags.bind(id, at: 1); _ = try tags.step()
        let topics = try connection.prepare("INSERT INTO note_topics VALUES (?, 'topic', 0.9, 1)")
        try topics.bind(id, at: 1); _ = try topics.step()
    }

    func vector(_ first: Double = 1, _ second: Double = 0) -> [Double] {
        [first, second] + Array(repeating: 0, count: 382)
    }

    func embedding(_ first: Double = 1, _ second: Double = 0) -> TextEmbedding {
        TextEmbedding(modelIdentifier: Self.model, vector: vector(first, second))
    }

    func blob(_ vector: [Double]) -> Data {
        var data = Data()
        for value in vector {
            var bits = Float(value).bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        return data
    }

    func rows(_ sql: String) throws -> [[String]] {
        let statement = try connection.prepare(sql)
        var result: [[String]] = []
        while try statement.step() { result.append([statement.string(at: 0)]) }
        return result
    }

    func scalar(_ sql: String) throws -> String { try rows(sql).first?.first ?? "" }
}
