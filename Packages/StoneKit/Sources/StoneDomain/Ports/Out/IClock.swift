import Foundation

/// The current time and the calendar that turns it into local days.
public protocol IClock: Sendable {
    var now: Date { get }
    var calendar: Calendar { get }
}
