import Foundation

public struct SQLiteDatabaseError: Error, CustomStringConvertible, Sendable {
    public let code: Int32
    public let message: String

    public var description: String { "SQLite search index (\(code)): \(message)" }

    public init(code: Int32, message: String) {
        self.code = code
        self.message = message
    }
}
