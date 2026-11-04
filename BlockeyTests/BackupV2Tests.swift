import Testing
import Foundation
import SwiftData
@testable import Blockey

/// Backup v2 (ADR 005, plan task 3.9, A.5).
///
/// Fixtures live in `Fixtures/` as real JSON files, so a change to the Codable shape that breaks
/// an old file fails here and not on the owner's phone. A throwaway `UserDefaults` suite per test
/// keeps settings restores away from the real preferences.
@Suite("Backup v2")
@MainActor
struct BackupV2Tests {

    private final class Anchor {}

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle(for: Anchor.self).url(forResource: name, withExtension: "json"),
                               "fixture \(name).json is not in the test bundle")
        return try Data(contentsOf: url)
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: TaskItem.self, DayTemplate.self, TemplateRow.self, TemplateAssignment.self,
            ActivityDay.self, CategoryDefinition.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "BackupV2Tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func definitions(_ context: ModelContext) throws -> [CategoryDefinition] {
        try context.fetch(FetchDescriptor<CategoryDefinition>()).sorted { $0.slug < $1.slug }
    }

    private func category(_ slug: String, hex: String? = nil, name: String = "N") -> BlockeyBackup.Category {
        .init(slug: slug, name: name, emoji: "x", symbolName: "star", paletteIndex: 7, sortIndex: 0,
              archivedAt: nil, customColorHex: hex)
    }

    // MARK: Decoding

    @Test("A v1 file decodes under the v2 shape, with no categories or settings")
    func v1FileDecodesUnderV2() throws {
        let backup = try BlockeyBackup.decode(try fixture("backup-v1"))
        #expect(backup.version == 1)
        #expect(backup.categories == nil)
        #expect(backup.settings == nil)
        #expect(backup.tasks.count == 2)
        #expect(backup.activityDays == ["2026-09-30", "2026-10-01"])
    }

    @Test("A v2 file decodes with a shape a v1 reader would also accept")
    func v2FileDecodesUnderV1Shape() throws {
        // What the build on the phone today does: synthesised Codable ignores unknown keys.
        struct V1Shape: Codable {
            var version: Int
            var tasks: [BlockeyBackup.Task]
            var templates: [BlockeyBackup.Template]
            var assignments: [BlockeyBackup.Assignment]
            var activityDays: [String]?
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let old = try decoder.decode(V1Shape.self, from: try fixture("backup-v2"))
        #expect(old.tasks.first?.category == "งานบ้าน")
    }

    @Test("A v2 file without customColorHex decodes, and the colour is nil")
    func v2FileWithoutCustomColorHexDecodes() throws {
        let backup = try BlockeyBackup.decode(try fixture("backup-v2-no-custom-color"))
        #expect(backup.categories?.count == 2)
        #expect(backup.categories?.allSatisfy { $0.customColorHex == nil } == true)
        let context = try makeContext()
        try backup.restore(into: context, defaults: try makeDefaults())
        #expect(try definitions(context).allSatisfy { $0.customColorHex == nil })
    }

    @Test("The new top-level fields are optional in the encoded form too")
    func newFieldsOptionalWhenEncodedFromV1() throws {
        var v1 = BlockeyBackup()
        v1.version = 1
        let data = try JSONEncoder().encode(v1)
        let reread = try JSONDecoder().decode(BlockeyBackup.self, from: data)
        #expect(reread.categories == nil && reread.settings == nil)
    }

    // MARK: Version gate

    @Test("A newer version is refused at decode, even when the rest of the shape is unknown")
    func decodeRefusesNewerVersion() throws {
        let json = #"{"version": 3, "exportedAt": "2026-11-04T09:00:00Z", "somethingNew": [1,2]}"#
        #expect(throws: BlockeyBackup.BackupError.newerVersion(3)) {
            _ = try BlockeyBackup.decode(Data(json.utf8))
        }
        #expect(BlockeyBackup.BackupError.newerVersion(3).localizedDescription
                == "This backup is from a newer version of Blockey. Update the app, then try again.")
    }

    @Test("Restore refuses a newer version and deletes nothing")
    func restoreRefusesNewerVersion() throws {
        let context = try makeContext()
        context.insert(TaskItem(title: "keep me"))
        context.insert(CategoryDefinition(slug: "mine", name: "Mine", emoji: "x", symbolName: "star",
                                          paletteIndex: 7, sortIndex: 0))
        try context.save()
        let defaults = try makeDefaults()

        var future = BlockeyBackup()
        future.version = BlockeyBackup.currentVersion + 1
        future.settings = .init(snapMinutes: 30)
        #expect(throws: BlockeyBackup.BackupError.newerVersion(3)) {
            try future.restore(into: context, defaults: defaults)
        }
        #expect(try context.fetchCount(FetchDescriptor<TaskItem>()) == 1)
        #expect(try definitions(context).count == 1)
        #expect(defaults.object(forKey: SettingsKey.snapMinutes) == nil)
    }

    // MARK: Round trip

    @Test("A v2 file restores categories, tasks and every setting")
    func v2RoundTripsCategoriesAndSettings() throws {
        let context = try makeContext()
        let defaults = try makeDefaults()
        let backup = try BlockeyBackup.decode(try fixture("backup-v2"))
        let result = try backup.restore(into: context, defaults: defaults)

        #expect(result.categories == 2)
        let rows = try definitions(context)
        #expect(Set(rows.map(\.slug)) == ["งานบ้าน", "reading"])
        let thai = try #require(rows.first { $0.slug == "งานบ้าน" })
        #expect(thai.customColorHex == "#1A2B3C" && thai.emoji == "🧹" && thai.paletteIndex == 8)
        let reading = try #require(rows.first { $0.slug == "reading" })
        #expect(reading.archivedAt != nil)

        #expect(defaults.integer(forKey: SettingsKey.dayStartMinute) == 480)
        #expect(defaults.integer(forKey: SettingsKey.dayEndMinute) == 1260)
        #expect(defaults.integer(forKey: SettingsKey.snapMinutes) == 30)
        #expect(defaults.string(forKey: SettingsKey.hiddenCalendarIDs) == "CAL-A\nCAL-B")
        #expect(defaults.bool(forKey: SettingsKey.alarmEnabled))
        #expect(defaults.integer(forKey: SettingsKey.alarmMinutesBefore) == 10)
        #expect(defaults.bool(forKey: SettingsKey.skipPlanPreview))
    }

    @Test("Capture then restore reproduces categories and settings")
    func captureRestoreRoundTrip() throws {
        let source = try makeContext()
        let sourceDefaults = try makeDefaults()
        sourceDefaults.set(600, forKey: SettingsKey.dayStartMinute)
        sourceDefaults.set(1200, forKey: SettingsKey.dayEndMinute)
        sourceDefaults.set(10, forKey: SettingsKey.snapMinutes)
        sourceDefaults.set("b\na", forKey: SettingsKey.hiddenCalendarIDs)
        source.insert(CategoryDefinition(slug: "gym", name: "Gym", emoji: "x", symbolName: "figure",
                                         paletteIndex: 9, sortIndex: 2, customColorHex: "#ABCDEF"))
        try source.save()

        let backup = try BlockeyBackup.capture(context: source, defaults: sourceDefaults)
        #expect(backup.version == 2)
        #expect(backup.settings?.hiddenCalendarIDs == ["a", "b"])
        // Unset keys are captured as their effective defaults.
        #expect(backup.settings?.alarmMinutesBefore == 5)
        #expect(backup.settings?.alarmEnabled == false)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let reread = try BlockeyBackup.decode(try encoder.encode(backup))

        let target = try makeContext()
        let targetDefaults = try makeDefaults()
        try reread.restore(into: target, defaults: targetDefaults)
        let gym = try #require(try definitions(target).first)
        #expect(gym.slug == "gym" && gym.customColorHex == "#ABCDEF" && gym.sortIndex == 2)
        #expect(targetDefaults.integer(forKey: SettingsKey.snapMinutes) == 10)
        #expect(targetDefaults.string(forKey: SettingsKey.hiddenCalendarIDs) == "a\nb")
        #expect(Calendar.current.isDate(reread.exportedAt, equalTo: backup.exportedAt, toGranularity: .second))
    }

    @Test("The streak still merges and tasks and templates still replace")
    func activityDaysStillMerge() throws {
        let context = try makeContext()
        context.insert(ActivityDay(key: "2026-01-01", recordedAt: .now))
        context.insert(TaskItem(title: "old"))
        try context.save()
        try BlockeyBackup.decode(try fixture("backup-v2")).restore(into: context, defaults: try makeDefaults())
        let keys = Set(try context.fetch(FetchDescriptor<ActivityDay>()).map(\.key))
        #expect(keys == ["2026-01-01", "2026-11-03"])
        #expect(try context.fetch(FetchDescriptor<TaskItem>()).map(\.title) == ["Water plants"])
    }

    // MARK: Categories

    @Test("A v1 file restores and leaves existing categories alone")
    func restoringV1FileKeepsExistingCategories() throws {
        let context = try makeContext()
        context.insert(CategoryDefinition(slug: "mine", name: "Mine", emoji: "x", symbolName: "star",
                                          paletteIndex: 7, sortIndex: 0))
        try context.save()
        let defaults = try makeDefaults()
        let result = try BlockeyBackup.decode(try fixture("backup-v1")).restore(into: context, defaults: defaults)
        #expect(result.tasks == 2 && result.templates == 1 && result.categories == 0)
        #expect(try definitions(context).map(\.slug) == ["mine"])
        #expect(defaults.object(forKey: SettingsKey.snapMinutes) == nil, "a v1 file must not touch settings")
    }

    @Test("nil and empty categories both change nothing")
    func nilAndEmptyCategoriesBehaveAsSpecified() throws {
        for value in [nil, [BlockeyBackup.Category]()] {
            let context = try makeContext()
            context.insert(CategoryDefinition(slug: "mine", name: "Mine", emoji: "x", symbolName: "star",
                                              paletteIndex: 7, sortIndex: 0))
            try context.save()
            var backup = BlockeyBackup()
            backup.categories = value
            try backup.restore(into: context, defaults: try makeDefaults())
            #expect(try definitions(context).map(\.slug) == ["mine"])
        }
    }

    @Test("Merge upserts by slug and never deletes a definition")
    func mergeUpsertsAndNeverDeletes() throws {
        let context = try makeContext()
        context.insert(CategoryDefinition(slug: "keep", name: "Keep", emoji: "k", symbolName: "star",
                                          paletteIndex: 7, sortIndex: 0, customColorHex: "#111111"))
        context.insert(CategoryDefinition(slug: "edit", name: "Old", emoji: "o", symbolName: "star",
                                          paletteIndex: 7, sortIndex: 1, customColorHex: "#222222"))
        try context.save()
        var backup = BlockeyBackup()
        backup.categories = [category("edit", hex: nil, name: "New"), category("added")]
        try backup.restore(into: context, defaults: try makeDefaults())

        let rows = try definitions(context)
        #expect(rows.map(\.slug) == ["added", "edit", "keep"])
        let edit = try #require(rows.first { $0.slug == "edit" })
        #expect(edit.name == "New")
        #expect(edit.customColorHex == nil, "the file's state wins for a definition it names")
        #expect(try #require(rows.first { $0.slug == "keep" }).customColorHex == "#111111")
    }

    @Test("Restore keeps unknown and archived slugs verbatim on tasks and rows")
    func restoreKeepsUnknownAndArchivedSlugsVerbatim() throws {
        let context = try makeContext()
        var backup = BlockeyBackup()
        backup.tasks = [.init(title: "a", estimatedMinutes: 30, category: "ghost", sortIndex: 0),
                        .init(title: "b", estimatedMinutes: 30, category: "ขยะ", sortIndex: 1)]
        backup.templates = [.init(id: UUID(), name: "T", rows: [
            .init(title: "r", startMinuteOfDay: 540, durationMinutes: 30, category: "ghost")])]
        var archived = category("old")
        archived.archivedAt = .now
        backup.categories = [archived]
        try backup.restore(into: context, defaults: try makeDefaults())
        let slugs = try context.fetch(FetchDescriptor<TaskItem>()).map(\.categoryRaw).sorted()
        #expect(slugs == ["ghost", "ขยะ"])
        #expect(try context.fetch(FetchDescriptor<TemplateRow>()).map(\.categoryRaw) == ["ghost"])
        #expect(try definitions(context).first?.archivedAt != nil)
    }

    @Test("A task whose slug has no definition still restores, resolving to a stand-in")
    func restoreTaskReferencingMissingCategoryGetsStandIn() throws {
        let context = try makeContext()
        var backup = BlockeyBackup()
        backup.tasks = [.init(title: "a", estimatedMinutes: 30, category: "ghost", sortIndex: 0)]
        try backup.restore(into: context, defaults: try makeDefaults())
        let task = try #require(try context.fetch(FetchDescriptor<TaskItem>()).first)
        let catalog = CategoryCatalog(definitions: try definitions(context).map(\.value))
        #expect(task.categoryRaw == "ghost")
        #expect(catalog.resolve(task.categoryRaw).slug == "ghost")
        #expect(try definitions(context).isEmpty)
    }

    @Test("Duplicate slugs in a file do not crash; the first wins and the rest are counted")
    func restoreDuplicateSlugsInFileDoesNotCrash() throws {
        var backup = BlockeyBackup()
        backup.categories = [category("dup", name: "First"), category("dup", name: "Second"),
                             category("   "), category("")]
        let plan = try backup.validated()
        #expect(plan.categories.count == 1 && plan.categoriesSkipped == 3)
        let context = try makeContext()
        try backup.restore(into: context, defaults: try makeDefaults())
        let rows = try definitions(context)
        #expect(rows.count == 1 && rows.first?.name == "First")
    }

    // MARK: Colour

    @Test("A valid customColorHex round-trips")
    func customColorHexRoundTrips() throws {
        let context = try makeContext()
        var backup = BlockeyBackup()
        backup.categories = [category("c", hex: "#0A1B2C")]
        try backup.restore(into: context, defaults: try makeDefaults())
        #expect(try definitions(context).first?.customColorHex == "#0A1B2C")
    }

    @Test("A lowercase hex is stored uppercase")
    func lowercaseCustomColorHexRestoresCanonical() throws {
        let context = try makeContext()
        var backup = BlockeyBackup()
        backup.categories = [category("c", hex: "#abcdef")]
        try backup.restore(into: context, defaults: try makeDefaults())
        #expect(try definitions(context).first?.customColorHex == "#ABCDEF")
    }

    @Test("An invalid hex restores as nil, on the palette index")
    func invalidCustomColorHexRestoresAsNilOnPaletteIndex() throws {
        let bad = ["red", "#FFF", "ABCDEF", "#ABCDEG", "#ABCDEF00", " #ABCDEF", "", "#ABCDEF\n"]
        for (i, hex) in bad.enumerated() {
            let context = try makeContext()
            var backup = BlockeyBackup()
            backup.categories = [category("c\(i)", hex: hex)]
            try backup.restore(into: context, defaults: try makeDefaults())
            let row = try #require(try definitions(context).first)
            #expect(row.customColorHex == nil, "\(hex.debugDescription) should not survive")
            #expect(row.paletteIndex == 7)
        }
    }

    // MARK: Settings

    @Test("Out-of-range settings are ignored or clamped, valid siblings still apply")
    func restoreSettingsClampsOutOfRangeValues() throws {
        let defaults = try makeDefaults()
        defaults.set(15, forKey: SettingsKey.snapMinutes)
        var backup = BlockeyBackup()
        backup.settings = .init(dayStartMinute: 900, dayEndMinute: 600,   // start after end
                                snapMinutes: 7,                           // not a snap option
                                alarmEnabled: true, alarmMinutesBefore: 500,
                                skipPlanPreview: true)
        let plan = try backup.validated()
        #expect(plan.settings.dayStartMinute == nil && plan.settings.dayEndMinute == nil)
        #expect(plan.settings.snapMinutes == nil)
        #expect(plan.settings.alarmMinutesBefore == 60)

        try backup.restore(into: try makeContext(), defaults: defaults)
        #expect(defaults.integer(forKey: SettingsKey.snapMinutes) == 15)
        #expect(defaults.object(forKey: SettingsKey.dayStartMinute) == nil)
        #expect(defaults.integer(forKey: SettingsKey.alarmMinutesBefore) == 60)
        #expect(defaults.bool(forKey: SettingsKey.skipPlanPreview))

        var other = BlockeyBackup()
        other.settings = .init(dayStartMinute: -1, dayEndMinute: 1441, alarmMinutesBefore: -5)
        let plan2 = try other.validated()
        #expect(plan2.settings.dayStartMinute == nil)
        #expect(plan2.settings.alarmMinutesBefore == 0)
        other.settings = .init(dayStartMinute: 0, dayEndMinute: 1440)
        #expect(try other.validated().settings.dayEndMinute == 1440)
        other.settings = .init(dayStartMinute: 480)
        #expect(try other.validated().settings.dayStartMinute == nil, "a lone half of the window is ignored")
    }

    @Test("A settings object with only some fields restores only those")
    func partialSettingsTouchOnlyWhatIsPresent() throws {
        let defaults = try makeDefaults()
        defaults.set(10, forKey: SettingsKey.snapMinutes)
        var backup = BlockeyBackup()
        backup.settings = .init(alarmEnabled: true)
        try backup.restore(into: try makeContext(), defaults: defaults)
        #expect(defaults.bool(forKey: SettingsKey.alarmEnabled))
        #expect(defaults.integer(forKey: SettingsKey.snapMinutes) == 10)
    }

    @Test("Unknown calendar IDs are kept; blank and newline-bearing ones are dropped")
    func restoreKeepsUnknownCalendarIDsHarmlessly() throws {
        let defaults = try makeDefaults()
        var backup = BlockeyBackup()
        backup.settings = .init(hiddenCalendarIDs: ["NOT-ON-THIS-PHONE", "", "a\nb"])
        try backup.restore(into: try makeContext(), defaults: defaults)
        #expect(defaults.string(forKey: SettingsKey.hiddenCalendarIDs) == "NOT-ON-THIS-PHONE")
    }

    @Test("One-time flags are neither captured nor restored")
    func oneTimeFlagsAreNotCarried() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: SettingsKey.hasSeenStarterTemplatesNote)
        defaults.set(true, forKey: SettingsKey.hasSeededStreak)
        let json = String(decoding: try JSONEncoder().encode(
            try BlockeyBackup.capture(context: try makeContext(), defaults: defaults)), as: UTF8.self)
        #expect(!json.contains("hasSeen") && !json.contains("hasSeeded"))
    }

    // MARK: Atomicity

    @Test("Everything is validated before the first delete")
    func restoreValidatesBeforeDeleting() throws {
        // The only validation failure today is the version gate, and it must beat every delete.
        let context = try makeContext()
        context.insert(TaskItem(title: "t"))
        context.insert(DayTemplate(name: "tpl"))
        context.insert(TemplateAssignment(weekday: 1, templateID: nil))
        try context.save()
        var future = BlockeyBackup()
        future.version = 99
        #expect(throws: BlockeyBackup.BackupError.self) { try future.restore(into: context) }
        #expect(try context.fetchCount(FetchDescriptor<TaskItem>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<DayTemplate>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<TemplateAssignment>()) == 1)
        #expect(!context.hasChanges)
    }

    // MARK: Warning

    private func pending(_ backup: BlockeyBackup, tasks: Int = 0, templates: Int = 0) -> PendingRestore {
        PendingRestore(backup: backup, existingTasks: tasks, existingTemplates: templates)
    }

    @Test("The restore warning counts categories, and says they are never deleted")
    func restoreWarningCountsCategories() {
        var backup = BlockeyBackup()
        backup.categories = [category("a"), category("b"), category("b")]
        let withLoss = pending(backup, tasks: 2, templates: 1).warning
        #expect(withLoss.contains("2 categories"), "duplicates must not be counted: \(withLoss)")
        #expect(withLoss.contains("never deleted"))

        backup.categories = [category("a")]
        #expect(pending(backup).warning.contains("1 category"))
        #expect(PendingRestore.counted(0, "category", plural: "categories") == "no categories")
    }

    @Test("The warning is unchanged for a v1 file, and mentions settings when the file has them")
    func warningForV1AndSettings() {
        let v1 = pending(BlockeyBackup())
        #expect(!v1.warning.contains("categor") && !v1.warning.contains("settings"))
        var backup = BlockeyBackup()
        backup.settings = .init(snapMinutes: 15)
        #expect(pending(backup).warning.contains("settings are restored"))
    }
}

@Suite("Backup v2 hostile files")
@MainActor
struct BackupV2HostileFileTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: TaskItem.self, DayTemplate.self, TemplateRow.self, TemplateAssignment.self,
            ActivityDay.self, CategoryDefinition.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    @Test("Repeated template IDs and weekdays in a file restore without crashing or leaving pending deletes")
    func duplicateTemplateIDsAndWeekdaysLeaveAConsistentStore() throws {
        let context = try makeContext()
        context.insert(TaskItem(title: "old"))
        try context.save()
        let id = UUID()
        var backup = BlockeyBackup()
        let row = BlockeyBackup.Template.Row(title: "r", startMinuteOfDay: 60, durationMinutes: 30, category: "work")
        backup.templates = [.init(id: id, name: "A", rows: [row]), .init(id: id, name: "B", rows: [row])]
        backup.assignments = [.init(weekday: 2, templateID: id), .init(weekday: 2, templateID: id)]
        _ = try? backup.restore(into: context, defaults: UserDefaults(suiteName: "BackupV2Hostile-\(UUID().uuidString)") ?? .standard)
        #expect(!context.hasChanges, "either saved or rolled back, never half-applied")
    }
}
