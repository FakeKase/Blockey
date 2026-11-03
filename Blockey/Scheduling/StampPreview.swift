import Foundation

/// What stamping a template would do, worked out ahead of time so the sheet can show it
/// before anything is written.
///
/// Pure: no EventKit, no SwiftUI, no SwiftData. It wraps the stamper's own `Result` and adds
/// the things a confirmation sheet needs, so the UI formats values and decides nothing.
///
/// A preview is a proposal, not a promise. The calendar can change between the moment the
/// sheet opens and the moment the user taps confirm (a meeting arrives, the clock passes a
/// row), so confirming recomputes and compares against this value. That is why it is
/// `Equatable`: the comparison is the staleness check.
struct StampPreview: Equatable, Sendable {

    /// How the stamp treats blocks already on the day.
    enum Mode: Equatable, Sendable {
        /// Add around what is there: own blocks and fixed events are both busy.
        case keep
        /// Delete own blocks first, then stamp into the emptied day.
        case startOver
    }

    /// One row of the sheet, as values. The UI chooses how to render them.
    struct Row: Equatable, Identifiable, Sendable {
        enum Kind: Equatable, Sendable {
            case placed(TimeRange)
            /// `from` is where the template asked for it.
            case moved(to: TimeRange, from: Date)
            /// Nowhere in the day holds it.
            case inbox

            var range: TimeRange? {
                switch self {
                case .placed(let r), .moved(let r, _): return r
                case .inbox: return nil
                }
            }
        }

        let id: UUID
        let title: String
        let kind: Kind

        /// The row's time, or `nil` for a row that goes to the inbox. `format` renders one
        /// instant, so the caller owns locale and 12/24-hour preference.
        func timeText(_ format: (Date) -> String) -> String? {
            kind.range.map { "\(format($0.start)) to \(format($0.end))" }
        }

        /// The row's note: why it is not simply where the template wanted it.
        func noteText(_ format: (Date) -> String) -> String? {
            switch kind {
            case .placed: return nil
            case .moved(_, let from): return "moved from \(format(from))"
            case .inbox: return "no room today"
            }
        }
    }

    /// Start of the day this preview is for.
    let day: Date
    let mode: Mode
    let result: TemplateStamper.Result
    let rows: [Row]
    /// Zero-length rows. They are not shown and never become inbox tasks: a task with no
    /// length is not a thing the user can act on.
    let droppedCount: Int

    /// What confirming writes.
    var confirmCount: Int { rows.filter { $0.kind != .inbox }.count }
    var inboxCount: Int { rows.count - confirmCount }
    var isConfirmDisabled: Bool { confirmCount == 0 }

    /// The template has no usable rows at all (none assigned, or empty).
    var hasNoRows: Bool { rows.isEmpty }
    /// There are rows, but none can be placed (the hours have passed, or the day is full).
    var nothingFits: Bool { !rows.isEmpty && confirmCount == 0 }

    init(result: TemplateStamper.Result, items: [TemplateStamper.Item], day: Date, mode: Mode,
         calendar: Calendar) {
        self.day = calendar.startOfDay(for: day)
        self.mode = mode
        self.result = result

        var dropped = 0
        var rows: [Row] = []
        for placement in result.placements {
            let item = placement.item
            switch placement.outcome {
            case .placedAtIntendedTime(let range):
                rows.append(Row(id: item.id, title: item.title, kind: .placed(range)))
            case .movedToFit(let range):
                let intended = DaySchedule.timeOfDay(item.startMinuteOfDay, on: day, calendar: calendar)
                rows.append(Row(id: item.id, title: item.title, kind: .moved(to: range, from: intended)))
            case .unplaced(.zeroDuration):
                dropped += 1
            case .unplaced(.noGapFitsInDayWindow):
                rows.append(Row(id: item.id, title: item.title, kind: .inbox))
            }
        }
        self.rows = rows
        self.droppedCount = dropped
    }

    // `rows` and `droppedCount` derive from `result`, so comparing them too would add nothing.
    static func == (lhs: StampPreview, rhs: StampPreview) -> Bool {
        lhs.day == rhs.day && lhs.mode == rhs.mode && lhs.result == rhs.result
    }

    // MARK: Building

    /// What the stamper must plan around in each mode.
    ///
    /// Fixed events are never freed. Start over deletes only our own *editable* blocks, and
    /// `DayContents.blocks.filter(\.isEditable)` is what `CalendarService.deleteAllBlocks`
    /// removes (same calendar, same day overlap, same editability rule; all-day set aside in
    /// both), with one exception: `contents` hides declined and cancelled events and the
    /// delete does not, so those go too. They consume no time either way, so the busy set is
    /// unaffected. Own blocks the clear leaves alone (recurring, multi-day) survive it, so
    /// they stay busy in both modes.
    static func busy(mode: Mode, fixed: [TimeRange], ownEditable: [TimeRange],
                     ownLocked: [TimeRange]) -> [TimeRange] {
        switch mode {
        case .keep: return fixed + ownEditable + ownLocked
        case .startOver: return fixed + ownLocked
        }
    }

    static func make(items: [TemplateStamper.Item],
                     on date: Date,
                     mode: Mode,
                     fixed: [TimeRange],
                     ownEditable: [TimeRange],
                     ownLocked: [TimeRange],
                     window: TimeRange,
                     notBefore: Date?,
                     calendar: Calendar) -> StampPreview {
        let result = TemplateStamper.stamp(items: items,
                                           on: date,
                                           busy: busy(mode: mode, fixed: fixed, ownEditable: ownEditable, ownLocked: ownLocked),
                                           window: window,
                                           notBefore: notBefore,
                                           calendar: calendar)
        return StampPreview(result: result, items: items, day: date, mode: mode, calendar: calendar)
    }

    // MARK: Title

    /// "Today", "Tomorrow", or the weekday name, for the sheet's heading.
    static func sheetTitle(for date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        let index = calendar.component(.weekday, from: date) - 1
        let names = calendar.weekdaySymbols
        return names.indices.contains(index) ? names[index] : ""
    }
}
