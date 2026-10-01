import Foundation
import StoneDomain

public final class SystemClock: IClock {
    public init() {}

    public var now: Date { Date() }
    /// Gregorian in the user's time zone: journal days are ISO dates in every region.
    public var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }
}
