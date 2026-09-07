import Foundation

/// A half-open interval of time: `[start, end)`.
///
/// Half-open is deliberate. Two ranges that merely touch — one ending exactly
/// where the next begins — do **not** overlap. Back-to-back meetings are the
/// common case in a real calendar and must never be reported as a conflict.
struct TimeRange: Equatable, Hashable, Sendable {
    let start: Date
    let end: Date

    /// `end` is clamped so a range can never run backwards.
    init(start: Date, end: Date) {
        self.start = start
        self.end = Swift.max(start, end)
    }

    init(start: Date, duration: TimeInterval) {
        self.init(start: start, end: start.addingTimeInterval(Swift.max(0, duration)))
    }

    var duration: TimeInterval { end.timeIntervalSince(start) }
    var isEmpty: Bool { duration <= 0 }

    func overlaps(_ other: TimeRange) -> Bool {
        start < other.end && other.start < end
    }

    func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }

    /// True when `other` lies entirely within this range.
    func contains(_ other: TimeRange) -> Bool {
        other.start >= start && other.end <= end
    }

    /// The portion of this range inside `bounds`, or `nil` when they are
    /// disjoint or touch at a single instant.
    func clamped(to bounds: TimeRange) -> TimeRange? {
        let s = Swift.max(start, bounds.start)
        let e = Swift.min(end, bounds.end)
        guard s < e else { return nil }
        return TimeRange(start: s, end: e)
    }

    func shifted(by interval: TimeInterval) -> TimeRange {
        TimeRange(start: start.addingTimeInterval(interval),
                  end: end.addingTimeInterval(interval))
    }
}
