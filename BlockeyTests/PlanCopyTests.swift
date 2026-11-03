import Testing
import Foundation
@testable import Blockey

@Suite("PlanCopy sentences")
struct PlanCopyTests {

    private let calendar = Calendar.current

    /// A preview built from the live calendar. Rows start at 9:00, 10:00 and so on on a day
    /// that is not today, so nothing depends on the machine's clock or calendar system.
    private func preview(rows: [(String, Int, Int)], busy: [TimeRange] = [],
                         mode: StampPreview.Mode = .keep) -> StampPreview {
        let day = calendar.startOfDay(for: .now)
        let window = TimeRange(start: day.addingTimeInterval(7 * 3600), end: day.addingTimeInterval(22 * 3600))
        let items = rows.map { TemplateStamper.Item(title: $0.0, startMinuteOfDay: $0.1, durationMinutes: $0.2) }
        return StampPreview.make(items: items, on: day, mode: mode, fixed: busy, ownEditable: [],
                                 ownLocked: [], window: window, notBefore: nil, calendar: calendar)
    }

    @Test("Confirm title: add, start over, and nothing fits")
    func confirmTitles() {
        let two = preview(rows: [("A", 9 * 60, 30), ("B", 11 * 60, 30)])
        #expect(PlanCopy.confirmTitle(for: two, deleting: 0, dayPhrase: "Monday") == "Add 2 blocks for Monday")
        let one = preview(rows: [("A", 9 * 60, 30)])
        #expect(PlanCopy.confirmTitle(for: one, deleting: 0, dayPhrase: "today") == "Add 1 block for today")
        let over = preview(rows: [("A", 9 * 60, 30), ("B", 11 * 60, 30)], mode: .startOver)
        #expect(PlanCopy.confirmTitle(for: over, deleting: 3, dayPhrase: "today") == "Delete 3 and add 2 blocks")
        let day = calendar.startOfDay(for: .now)
        let full = preview(rows: [("A", 9 * 60, 30)],
                           busy: [TimeRange(start: day, end: day.addingTimeInterval(24 * 3600))])
        #expect(PlanCopy.confirmTitle(for: full, deleting: 0, dayPhrase: "today") == "Nothing fits")
    }

    @Test("Count line joins blocks, moves and inbox rows")
    func countLine() {
        let day = calendar.startOfDay(for: .now)
        // A meeting at 9 moves the 9:00 row; the second row cannot fit anywhere.
        let meeting = TimeRange(start: day.addingTimeInterval(9 * 3600), end: day.addingTimeInterval(10 * 3600))
        let p = preview(rows: [("A", 9 * 60, 60), ("B", 12 * 60, 60), ("C", 8 * 60, 20 * 60)], busy: [meeting])
        #expect(PlanCopy.countLine(for: p) == "2 blocks \u{00B7} 1 moved to fit \u{00B7} 1 to your inbox")
        let plain = preview(rows: [("A", 9 * 60, 60)])
        #expect(PlanCopy.countLine(for: plain) == "1 block")
    }

    @Test("Start over warnings include the untagged and kept sentences only when they apply")
    func startOverWarnings() {
        let base = PlanCopy.startOverWarnings(deleting: 3, untagged: 0, kept: 0, dayPhrase: "Monday")
        #expect(base == ["Deletes 3 blocks on Monday, including any you placed by hand. Blocks that came from your inbox go back to your inbox. Your meetings are not touched."])
        let today = PlanCopy.startOverWarnings(deleting: 1, untagged: 0, kept: 0, dayPhrase: "today")
        #expect(today[0].hasPrefix("Deletes 1 block today, including"))
        let full = PlanCopy.startOverWarnings(deleting: 3, untagged: 1, kept: 2, dayPhrase: "Monday")
        #expect(full.count == 3)
        #expect(full[1] == "One block has lost its Blockey tag, so it cannot be returned to the inbox. It will be deleted for good.")
        #expect(full[2] == "2 repeating or multi-day blocks stay where they are.")
        #expect(PlanCopy.startOverWarnings(deleting: 1, untagged: 0, kept: 1, dayPhrase: "Monday")[1]
                == "1 repeating or multi-day block stays where it is.")
    }

    @Test("The untagged-loss sentence has a plural form")
    func untaggedPlural() {
        #expect(PlanCopy.untaggedLoss(count: 2)
                == "2 blocks have lost their Blockey tag, so they cannot be returned to the inbox. They will be deleted for good.")
    }

    @Test("Inbox and Place-all copy, with the template-name fallback")
    func inboxAndFill() {
        #expect(PlanCopy.inboxNote(templateName: "Workday") == "from Workday, no room")
        #expect(PlanCopy.inboxNote(templateName: nil) == "from your template, no room")
        #expect(PlanCopy.placeAllTitle(count: 4, dayPhrase: "today") == "Place all 4 for today")
        #expect(PlanCopy.placeAllTitle(count: 1, dayPhrase: "Thursday") == "Place 1 for Thursday")
        #expect(PlanCopy.placeAllTitle(count: 4, fitting: 2, dayPhrase: "today") == "Place what fits for today")
        #expect(PlanCopy.placeAllTitle(count: 4, fitting: 4, dayPhrase: "today") == "Place all 4 for today")
        // None fitting keeps the plain title: the button is disabled and the reason is shown.
        #expect(PlanCopy.placeAllTitle(count: 4, fitting: 0, dayPhrase: "today") == "Place all 4 for today")
        #expect(PlanCopy.placeAllReason(isToday: true, dayPhrase: "today") == "Nothing fits in the time you have left.")
        #expect(PlanCopy.placeAllReason(isToday: false, dayPhrase: "Thursday") == "Nothing fits on Thursday.")
        #expect(PlanCopy.nothingFits(isToday: true) == "Your day is full from now on. Try tomorrow.")
        #expect(PlanCopy.nothingFits(isToday: false) == "Your meetings fill this day. Nothing fits.")
        #expect(PlanCopy.zeroLength(count: 1) == "1 row has no length and was skipped.")
    }
}

@Suite("The banner in the inbox tray")
struct PlanBannerTrayTests {
    @Test("Dropping the action keeps the id and the Undo record, so the banner carries over")
    func withoutActionKeepsIdentity() {
        let day = Calendar.current.startOfDay(for: .now)
        let window = TimeRange(start: day, end: day.addingTimeInterval(3600))
        let inputs = DayPlanInputs(date: day, now: day, isToday: false, window: window,
                                   plannableWindow: window, alarmMinutesBefore: nil,
                                   calendar: .current, hiddenCalendarIDs: [])
        let block = Block(title: "A", range: window, kind: .block(nil), isAllDay: false)
        let record = UndoRecord(inputs: inputs, created: [block])
        let banner = PlanBanner(text: "x", undo: record, action: .openInbox)
        let inTray = banner.withoutAction
        #expect(inTray.action == nil)
        #expect(inTray.id == banner.id)
        #expect(inTray.undo === record)
        #expect(inTray.lifetime == banner.lifetime)
    }
}

@Suite("Backup carries the template name")
@MainActor
struct BackupTemplateNameTests {
    @Test("An old backup without the field still decodes")
    func oldBackupDecodes() throws {
        let json = #"{"title":"A","estimatedMinutes":30,"category":"deep","sortIndex":1}"#
        let task = try JSONDecoder().decode(BlockeyBackup.Task.self, from: Data(json.utf8))
        #expect(task.droppedFromTemplateName == nil)
        #expect(task.droppedFromTemplate == nil)
    }
}
