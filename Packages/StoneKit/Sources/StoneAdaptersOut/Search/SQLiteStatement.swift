import CSQLite
import Foundation

final class SQLiteStatement {
    private let connection: SQLiteConnection
    private let handle: OpaquePointer

    init(connection: SQLiteConnection, sql: String) throws {
        self.connection = connection
        var prepared: OpaquePointer?
        let status = sqlite3_prepare_v2(connection.handle, sql, -1, &prepared, nil)
        guard status == SQLITE_OK, let prepared else { throw connection.error(status) }
        handle = prepared
    }

    deinit { sqlite3_finalize(handle) }

    func bind(_ value: String, at index: Int32) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let status = value.withCString { sqlite3_bind_text(handle, index, $0, Int32(value.utf8.count), transient) }
        try check(status)
    }

    func bind(_ value: Int64, at index: Int32) throws { try check(sqlite3_bind_int64(handle, index, value)) }
    func bind(_ value: Double, at index: Int32) throws { try check(sqlite3_bind_double(handle, index, value)) }

    func bind(_ value: Data, at index: Int32) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let status = value.withUnsafeBytes {
            sqlite3_bind_blob(handle, index, $0.baseAddress, Int32($0.count), transient)
        }
        try check(status)
    }

    func step() throws -> Bool {
        let status = sqlite3_step(handle)
        if status == SQLITE_ROW { return true }
        if status == SQLITE_DONE { return false }
        throw connection.error(status)
    }

    func reset() throws {
        try check(sqlite3_reset(handle))
        try check(sqlite3_clear_bindings(handle))
    }

    func string(at column: Int32) -> String {
        guard let bytes = sqlite3_column_text(handle, column) else { return "" }
        return String(decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(handle, column))), as: UTF8.self)
    }

    func integer(at column: Int32) -> Int64 { sqlite3_column_int64(handle, column) }
    func double(at column: Int32) -> Double { sqlite3_column_double(handle, column) }
    func isNull(at column: Int32) -> Bool { sqlite3_column_type(handle, column) == SQLITE_NULL }

    func data(at column: Int32) -> Data {
        guard let bytes = sqlite3_column_blob(handle, column) else { return Data() }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(handle, column)))
    }

    private func check(_ status: Int32) throws {
        guard status == SQLITE_OK else { throw connection.error(status) }
    }
}
