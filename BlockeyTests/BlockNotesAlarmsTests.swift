import Testing
import Foundation
import EventKit
@testable import Blockey

/// `Block.init(event:)` is the only place notes and alarms are read (ADR 007). An unsaved
/// `EKEvent` is enough: nothing here touches a calendar or asks for access.
@Suite("Block reads notes and alarm offsets")
struct BlockNotesAlarmsTests {

    private func event(start: Date) -> EKEvent {
        let event = EKEvent(eventStore: EKEventStore())
        event.title = "Write"
        event.startDate = start
        event.endDate = start.addingTimeInterval(3600)
        return event
    }

    @Test("Notes are copied and relative alarms keep their offsets, sorted")
    func notesAndRelativeAlarms() {
        let start = Calendar.current.startOfDay(for: .now).addingTimeInterval(9 * 3600)
        let e = event(start: start)
        e.notes = "Bring the laptop"
        e.addAlarm(EKAlarm(relativeOffset: -600))
        e.addAlarm(EKAlarm(relativeOffset: -3600))

        let block = Block(event: e, blockeyCalendarID: nil)

        #expect(block.notes == "Bring the laptop")
        #expect(block.alarmOffsets == [-3600, -600])
    }

    @Test("An absolute-date alarm becomes its offset from the event start")
    func absoluteAlarmBecomesOffset() {
        let start = Calendar.current.startOfDay(for: .now).addingTimeInterval(9 * 3600)
        let e = event(start: start)
        e.addAlarm(EKAlarm(absoluteDate: start.addingTimeInterval(-1800)))

        #expect(Block(event: e, blockeyCalendarID: nil).alarmOffsets == [-1800])
    }

    @Test("No notes and no alarms read as nil and empty")
    func nothingToRead() {
        let block = Block(event: event(start: .now), blockeyCalendarID: nil)
        #expect(block.notes == nil)
        #expect(block.alarmOffsets.isEmpty)
    }
}
