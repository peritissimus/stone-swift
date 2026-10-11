import CSQLite
import Foundation

/// Owned only by the search actor. Statements retain it until they are finalized.
final class SQLiteConnection {
    let handle: OpaquePointer

    init(databaseURL: URL) throws {
        guard databaseURL.isFileURL else {
            throw SQLiteDatabaseError(code: SQLITE_CANTOPEN, message: "A local database URL is required")
        }
        var opened: OpaquePointer?
        let status = sqlite3_open_v2(
            databaseURL.path, &opened, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK, let opened else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            if let opened { sqlite3_close_v2(opened) }
            throw SQLiteDatabaseError(code: status, message: message)
        }
        handle = opened
        sqlite3_busy_timeout(handle, 5_000)
    }

    deinit { sqlite3_close_v2(handle) }

    func error(_ code: Int32) -> SQLiteDatabaseError {
        SQLiteDatabaseError(code: code, message: String(cString: sqlite3_errmsg(handle)))
    }

    func execute(_ sql: String) throws {
        let status = sqlite3_exec(handle, sql, nil, nil, nil)
        guard status == SQLITE_OK else { throw error(status) }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        try SQLiteStatement(connection: self, sql: sql)
    }

    func transaction(_ operation: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try operation()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
}
