import Foundation

/// Pure day-planning arithmetic: what is busy, what is free, and where a block
/// can land.
///
/// Deliberately contains no EventKit, no SwiftUI and no persistence. Every
/// scheduling rule in the app lives here so it can be unit-tested directly,
/// without a calendar store or a running app.
enum DaySchedule {

    /// Collapses overlapping and touching ranges into a minimal sorted set.
    ///
    /// Touching ranges are merged (unlike `overlaps`, which treats them as
    /// distinct): for the purpose of finding free time, 9–10 and 10–11 are one
    /// solid block of busy from 9 to 11, with no usable gap between them.
    static func merge(_ ranges: [TimeRange]) -> [TimeRange] {
        let sorted = ranges.filter { !$0.isEmpty }.sorted { $0.start < $1.start }
        guard var current = sorted.first else { return [] }

        var merged: [TimeRange] = []
        for range in sorted.dropFirst() {
            if range.start <= current.end {
                current = TimeRange(start: current.start,
                                    end: Swift.max(current.end, range.end))
            } else {
                merged.append(current)
                current = range
            }
        }
        merged.append(current)
        return merged
    }

    /// Free space inside `window`, given everything in `busy`.
    ///
    /// Busy ranges may overlap, nest, or extend past the window — all are
    /// handled. Gaps shorter than `minimumDuration` are discarded: a
    /// four-minute sliver between meetings is not a planning slot.
    static func gaps(busy: [TimeRange],
                     within window: TimeRange,
                     minimumDuration: TimeInterval = 0) -> [TimeRange] {
        guard !window.isEmpty else { return [] }
        let blocked = merge(busy.compactMap { $0.clamped(to: window) })

        var free: [TimeRange] = []
        var cursor = window.start
        for range in blocked {
            if cursor < range.start {
                free.append(TimeRange(start: cursor, end: range.start))
            }
            cursor = Swift.max(cursor, range.end)
        }
        if cursor < window.end {
            free.append(TimeRange(start: cursor, end: window.end))
        }
        return free.filter { !$0.isEmpty && $0.duration >= minimumDuration }
    }

    /// The earliest slot of length `duration` among `gaps`.
    ///
    /// `notBefore` trims candidate gaps, which is what stops "fill my day" from
    /// scheduling work into hours that have already passed.
    static func firstFit(duration: TimeInterval,
                         in gaps: [TimeRange],
                         notBefore: Date? = nil) -> TimeRange? {
        guard duration > 0 else { return nil }
        for gap in gaps {
            var usable = gap
            if let notBefore, notBefore > gap.start {
                guard let trimmed = gap.clamped(to: TimeRange(start: notBefore, end: gap.end)) else { continue }
                usable = trimmed
            }
            if usable.duration >= duration {
                return TimeRange(start: usable.start, duration: duration)
            }
        }
        return nil
    }

    /// Rounds `date` onto a `minutes`-wide grid anchored at the start of its day.
    ///
    /// Anchoring at midnight rather than the epoch keeps the grid aligned to
    /// wall-clock time across time zones and DST shifts.
    static func snap(_ date: Date,
                     toMinutes minutes: Int,
                     calendar: Calendar = .current,
                     rounding: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> Date {
        guard minutes > 0 else { return date }
        let step = TimeInterval(minutes * 60)
        let anchor = calendar.startOfDay(for: date)
        let offset = date.timeIntervalSince(anchor)
        return anchor.addingTimeInterval((offset / step).rounded(rounding) * step)
    }

    /// A wall-clock time on a given day.
    ///
    /// `startOfDay + minutes * 60` is wrong on the two days a year that are not
    /// 24 hours long. On a spring-forward day it lands an hour late, on a
    /// fall-back day an hour early — which would shift the planning window and
    /// every block a template stamps, while still reporting them as placed at
    /// their intended time.
    static func timeOfDay(_ minuteOfDay: Int,
                          on date: Date,
                          calendar: Calendar = .current) -> Date {
        let midnight = calendar.startOfDay(for: date)
        let hour = minuteOfDay / 60
        let minute = minuteOfDay % 60
        if (0..<24).contains(hour),
           let exact = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: midnight) {
            return exact
        }
        // A minute-of-day at or past 24:00 has no wall-clock equivalent that
        // day; fall back to elapsed time from midnight.
        return midnight.addingTimeInterval(TimeInterval(minuteOfDay * 60))
    }

    /// The planning window for `date`, expressed as minutes from midnight.
    static func window(for date: Date,
                       startMinute: Int,
                       endMinute: Int,
                       calendar: Calendar = .current) -> TimeRange {
        TimeRange(start: timeOfDay(startMinute, on: date, calendar: calendar),
                  end: timeOfDay(endMinute, on: date, calendar: calendar))
    }
}
