import Foundation

extension Calendar {
    /// The top of the hour containing `date`.
    ///
    /// Written with `dateComponents` rather than `date(bySetting:)`, which
    /// searches *forward* for a matching component and would push 07:00 to
    /// 08:00 rather than leaving it alone.
    func flooredToHour(_ date: Date) -> Date {
        self.date(from: dateComponents([.year, .month, .day, .hour], from: date)) ?? date
    }

    /// The top of the next hour, or `date` itself when already exact.
    ///
    /// Steps forward rather than adding a single hour: inside the repeated hour
    /// of a fall-back day, `flooredToHour` resolves to the *first* occurrence,
    /// so one addition can still land before the input.
    func ceiledToHour(_ date: Date) -> Date {
        var candidate = flooredToHour(date)
        while candidate < date { candidate = candidate.addingTimeInterval(3600) }
        return candidate
    }

    func isSameDay(_ a: Date, _ b: Date) -> Bool {
        isDate(a, inSameDayAs: b)
    }
}
