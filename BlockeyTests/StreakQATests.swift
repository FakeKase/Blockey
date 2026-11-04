import Testing
import Foundation
import SwiftData
@testable import Blockey

/// QA additions for issue #7. Pure CivilDay arithmetic needs no Date, so fixed Gregorian
/// components are fine here (no Calendar.current involved).
@Suite("Streak QA")
@MainActor
struct StreakQATests {

    @Test("Year end, leap years and the 1900/2100 non-leap centuries step correctly")
    func civilArithmetic() {
        #expect(CivilDay(year: 2026, month: 12, day: 31).adding(days: 1) == CivilDay(year: 2027, month: 1, day: 1))
        #expect(CivilDay(year: 2024, month: 2, day: 28).adding(days: 1) == CivilDay(year: 2024, month: 2, day: 29))
        #expect(CivilDay(year: 2100, month: 2, day: 28).adding(days: 1) == CivilDay(year: 2100, month: 3, day: 1))
        #expect(CivilDay(year: 2000, month: 2, day: 28).adding(days: 1) == CivilDay(year: 2000, month: 2, day: 29))
        #expect(CivilDay(year: 1970, month: 1, day: 1).dayNumber == 0)
        #expect(CivilDay(key: "2100-02-29") == nil)
        #expect(CivilDay(key: "2024-02-29") != nil)
    }

    @Test("Key parsing rejects signs and whitespace so one day has one canonical key")
    func keyParsingIsStrict() {
        #expect(CivilDay(key: "2026-+1-05") == nil)
        #expect(CivilDay(key: "+026-01-05") == nil)
        #expect(CivilDay(key: " 026-01-05") == nil)
        #expect(CivilDay(key: "2026-01-05 ") == nil)
        #expect(CivilDay(key: "2026-1-5") == nil)
    }

    @Test("Restore does not store two rows for the same day under different spellings")
    func restoreDoesNotDuplicateNonCanonicalKeys() throws {
        let container = try ModelContainer(
            for: TaskItem.self, DayTemplate.self, TemplateRow.self, TemplateAssignment.self, ActivityDay.self, CategoryDefinition.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(BlockeyBackup.self, from: Data("""
        {"version":1,"exportedAt":"2026-10-01T09:00:00Z","tasks":[],"templates":[],"assignments":[],
         "activityDays":["2026-01-05","2026-+1-05"]}
        """.utf8))
        try backup.restore(into: context)
        let keys = try context.fetch(FetchDescriptor<ActivityDay>()).map(\.key)
        #expect(keys == ["2026-01-05"])
    }
}
