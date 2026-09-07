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
    func ceiledToHour(_ date: Date) -> Date {
        let floored = flooredToHour(date)
        return floored == date ? date : floored.addingTimeInterval(3600)
    }

    func isSameDay(_ a: Date, _ b: Date) -> Bool {
        isDate(a, inSameDayAs: b)
    }
}
