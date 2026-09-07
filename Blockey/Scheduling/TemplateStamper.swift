import Foundation

/// Applies a day template to a date, working around what is already scheduled.
///
/// The rule, in priority order:
///   1. Fixed events always win — stamping never moves a real meeting.
///   2. Try the item's intended time.
///   3. Otherwise take the next gap that fits, at or after the intended time.
///   4. Otherwise take any gap that fits, earlier in the day.
///   5. Otherwise leave it unplaced — the caller drops it into the inbox.
///
/// Items are placed in order, and each placement immediately becomes busy for
/// the items after it, so a template can never double-book itself.
enum TemplateStamper {

    /// A template row, flattened to the minimum the algorithm needs. Keeping
    /// this free of SwiftData lets the whole stamper be tested with literals.
    struct Item: Equatable, Identifiable, Sendable {
        let id: UUID
        let title: String
        let startMinuteOfDay: Int
        let durationMinutes: Int

        init(id: UUID = UUID(), title: String, startMinuteOfDay: Int, durationMinutes: Int) {
            self.id = id
            self.title = title
            self.startMinuteOfDay = startMinuteOfDay
            self.durationMinutes = durationMinutes
        }

        var duration: TimeInterval { TimeInterval(durationMinutes * 60) }
    }

    enum Outcome: Equatable, Sendable {
        /// Landed exactly where the template asked.
        case placedAtIntendedTime(TimeRange)
        /// Something was in the way; this is where it actually fits.
        case movedToFit(TimeRange)
        /// Nowhere in the day holds it. Becomes an inbox task.
        case unplaced(Reason)

        enum Reason: Equatable, Sendable {
            case noGapFitsInDayWindow
            case zeroDuration
        }

        var range: TimeRange? {
            switch self {
            case .placedAtIntendedTime(let r), .movedToFit(let r): return r
            case .unplaced: return nil
            }
        }

        var wasMoved: Bool {
            if case .movedToFit = self { return true }
            return false
        }
    }

    struct Placement: Equatable, Identifiable, Sendable {
        let item: Item
        let outcome: Outcome
        var id: UUID { item.id }
    }

    struct Result: Equatable, Sendable {
        let placements: [Placement]

        /// Items that found a home, ready to be written as calendar events.
        var scheduled: [(item: Item, range: TimeRange)] {
            placements.compactMap { placement in
                placement.outcome.range.map { (placement.item, $0) }
            }
        }

        /// Items that did not fit, destined for the inbox.
        var unplaced: [Item] {
            placements.filter { $0.outcome.range == nil }.map(\.item)
        }

        var movedCount: Int { placements.filter { $0.outcome.wasMoved }.count }

        static func == (lhs: Result, rhs: Result) -> Bool { lhs.placements == rhs.placements }
    }

    /// Stamps `items` onto `date`.
    ///
    /// - Parameters:
    ///   - busy: existing commitments — real meetings and any blocks already there.
    ///   - window: the user's planning window (e.g. 07:00–22:00).
    ///
    /// The window is widened to cover any item whose intended time falls outside
    /// it, so a 06:00 workout in a template stays at 06:00 rather than being
    /// silently dragged into working hours.
    static func stamp(items: [Item],
                      on date: Date,
                      busy: [TimeRange],
                      window: TimeRange,
                      calendar: Calendar = .current) -> Result {
        let midnight = calendar.startOfDay(for: date)
        let valid = items.filter { $0.durationMinutes > 0 }

        func intendedRange(_ item: Item) -> TimeRange {
            TimeRange(start: midnight.addingTimeInterval(TimeInterval(item.startMinuteOfDay * 60)),
                      duration: item.duration)
        }

        // Widen the window so the template's own intentions are always reachable.
        var effective = window
        for item in valid {
            let intended = intendedRange(item)
            effective = TimeRange(start: Swift.min(effective.start, intended.start),
                                  end: Swift.max(effective.end, intended.end))
        }

        var occupied = busy
        var placements: [Placement] = []

        for item in items.sorted(by: { $0.startMinuteOfDay < $1.startMinuteOfDay }) {
            guard item.durationMinutes > 0 else {
                placements.append(Placement(item: item, outcome: .unplaced(.zeroDuration)))
                continue
            }

            let intended = intendedRange(item)
            let free = DaySchedule.gaps(busy: occupied, within: effective)

            if free.contains(where: { $0.contains(intended) }) {
                occupied.append(intended)
                placements.append(Placement(item: item, outcome: .placedAtIntendedTime(intended)))
            } else if let later = DaySchedule.firstFit(duration: item.duration, in: free, notBefore: intended.start) {
                occupied.append(later)
                placements.append(Placement(item: item, outcome: .movedToFit(later)))
            } else if let anywhere = DaySchedule.firstFit(duration: item.duration, in: free) {
                occupied.append(anywhere)
                placements.append(Placement(item: item, outcome: .movedToFit(anywhere)))
            } else {
                placements.append(Placement(item: item, outcome: .unplaced(.noGapFitsInDayWindow)))
            }
        }

        return Result(placements: placements)
    }
}
