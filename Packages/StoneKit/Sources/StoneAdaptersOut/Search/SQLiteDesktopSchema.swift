import CSQLite
import Foundation

/// Checks compatibility without running desktop migrations or changing its schema version.
enum SQLiteDesktopSchema {
    static func workspaceID(in connection: SQLiteConnection, workspaceURL: URL) throws -> String {
        let required: [String: Set<String>] = [
            "workspaces": ["id", "folder_path"],
            "notes": ["id", "title", "file_path", "workspace_id", "is_deleted", "created_at", "updated_at"],
            "note_chunks": ["id", "note_id", "workspace_id", "chunk_index", "heading_path", "text", "content_hash",
                            "token_count", "embedding", "created_at", "updated_at"],
            "note_index_records": ["note_id", "workspace_id", "content_hash", "chunk_count", "indexed_at", "model",
                                   "dimensions", "status", "error"],
            "note_chunks_fts": ["chunk_id", "note_id", "workspace_id", "title", "heading_path", "text"],
        ]
        for (table, expected) in required {
            let statement = try connection.prepare("PRAGMA table_info(\(table))")
            var columns: Set<String> = []
            while try statement.step() { columns.insert(statement.string(at: 1)) }
            guard expected.isSubset(of: columns) else {
                throw SQLiteDatabaseError(code: SQLITE_SCHEMA, message: "Stone desktop search schema is missing required \(table) columns")
            }
        }
        guard workspaceURL.isFileURL else {
            throw SQLiteDatabaseError(code: SQLITE_NOTFOUND, message: "A local Stone workspace is required")
        }
        let suppliedPath = workspaceURL.standardizedFileURL.path
        let workspace = try connection.prepare("SELECT id FROM workspaces WHERE folder_path = ?")
        try workspace.bind(suppliedPath, at: 1)
        if try workspace.step() { return workspace.string(at: 0) }

        let canonicalPath = workspaceURL.standardizedFileURL.resolvingSymlinksInPath().path
        let aliases = try connection.prepare("SELECT id, folder_path FROM workspaces")
        var matches: [String] = []
        while try aliases.step() {
            let folder = aliases.string(at: 1)
            guard folder.hasPrefix("/") else { continue }
            if URL(fileURLWithPath: folder).standardizedFileURL.resolvingSymlinksInPath().path == canonicalPath {
                matches.append(aliases.string(at: 0))
            }
        }
        guard matches.count == 1, let match = matches.first else {
            let message = matches.isEmpty ? "This workspace is not registered in the Stone desktop database"
                : "Multiple Stone workspaces resolve to this folder; use the registered workspace path"
            throw SQLiteDatabaseError(code: SQLITE_NOTFOUND, message: message)
        }
        return match
    }

    static func prepareBookkeeping(in connection: SQLiteConnection) throws {
        // The sole Swift-owned table retains filesystem precision; desktop dates are integer seconds.
        try connection.execute("""
            CREATE TABLE IF NOT EXISTS stone_swift_index_state (
                note_id TEXT PRIMARY KEY NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
                workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
                source_mtime REAL NOT NULL,
                content_hash TEXT NOT NULL
            )
            """)
        let check = try connection.prepare("PRAGMA table_info(stone_swift_index_state)")
        var columns: Set<String> = []
        while try check.step() { columns.insert(check.string(at: 1)) }
        guard Set(["note_id", "workspace_id", "source_mtime", "content_hash"]).isSubset(of: columns) else {
            throw SQLiteDatabaseError(code: SQLITE_SCHEMA, message: "Swift search bookkeeping schema is incompatible")
        }
    }
}
