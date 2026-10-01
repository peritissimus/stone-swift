import Foundation

/// A local calendar day, spelled `YYYY-MM-DD` — the journal file's name and its title.
public struct JournalDate: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) throws {
        var probe = Calendar(identifier: .gregorian)
        probe.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(year: year, month: month, day: day)
        guard (1...9999).contains(year), components.isValidDate(in: probe) else {
            throw NoteError.invalidPath(String(format: "%04d-%02d-%02d", year, month, day))
        }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Only the calendar's time zone is used: file names are ISO days whatever calendar the user reads.
    public init(date: Date, calendar: Calendar) {
        let parts = Self.gregorian(in: calendar.timeZone).dateComponents([.year, .month, .day], from: date)
        year = parts.year ?? 1970
        month = parts.month ?? 1
        day = parts.day ?? 1
    }

    /// Nil for anything that is not a strict `YYYY-MM-DD` day.
    public init?(parsing text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
            let date = try? JournalDate(year: year, month: month, day: day)
        else { return nil }
        self = date
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public func adding(days: Int, calendar: Calendar) -> JournalDate {
        let gregorian = Self.gregorian(in: calendar.timeZone)
        let start = gregorian.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
        let shifted = gregorian.date(byAdding: .day, value: days, to: start) ?? start
        return JournalDate(date: shifted, calendar: gregorian)
    }

    private static func gregorian(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    public static func < (lhs: JournalDate, rhs: JournalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
