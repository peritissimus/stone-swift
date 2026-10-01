/// A wall-clock minute, rendered as Stone's 24-hour `[HH:MM]` capture stamp.
public struct ClockTime: Hashable, Sendable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    public var stamp: String {
        "[" + (hour < 10 ? "0" : "") + "\(hour):" + (minute < 10 ? "0" : "") + "\(minute)]"
    }
}
