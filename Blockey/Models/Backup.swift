import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// A portable copy of everything that lives only on this device.
///
/// Blocks are deliberately absent: they are calendar events and are already
/// safe outside the app. What is at risk is tasks and templates, and only in
/// one situation — deleting the app from the Home Screen. Re-signing and
/// reinstalling preserve them (see docs/adr/003).
///
/// Needs no entitlement and no App Group, so it works under free-provisioned
/// sideloading where CloudKit does not.
struct BlockeyBackup: Codable {
    /// The newest format this build can read. A file above it is refused before anything is
    /// deleted (ADR 005, "Backup v2"). Version 2 added `categories` and `settings`; both are
    /// optional, so a version 1 file still decodes and restores.
    static let currentVersion = 2

    var version = BlockeyBackup.currentVersion
    var exportedAt = Date()
    var tasks: [Task] = []
    var templates: [Template] = []
    var assignments: [Assignment] = []
    /// Days with an add, as Gregorian `yyyy-MM-dd` keys (issue #7). Optional and additive, so a
    /// backup written before the streak existed still decodes and `version` stays 1. Restore
    /// merges these in rather than replacing: a streak is history, and a stale backup must not
    /// shorten the one on the phone.
    var activityDays: [String]?
    /// Custom categories and customised built-ins (ADR 005). `nil` means the file predates
    /// categories (any v1 file); `[]` means a v2 phone with no customisations. Both change nothing
    /// on restore, and that is deliberate: do not "fix" `[]` into a wipe.
    var categories: [Category]?
    /// Absent in v1 files. Every field is optional on its own, so a file that carries only some of
    /// them restores only those.
    var settings: Settings?

    struct Category: Codable {
        var slug: String
        var name: String
        var emoji: String
        var symbolName: String
        var paletteIndex: Int
        var sortIndex: Int
        var archivedAt: Date?
        /// `#RRGGBB` sRGB, permanently (ADR 005 amendment). Optional so a v2 file written before
        /// the field existed still decodes. Restore canonicalises it: valid becomes uppercase,
        /// anything else becomes nil and the category falls back to its `paletteIndex`.
        var customColorHex: String?
    }

    /// The preferences that live in `UserDefaults` under `SettingsKey`.
    ///
    /// Carried: the planning window, snap, hidden calendars, alerts and Skip preview. Not carried:
    /// `hasSeededStarterTemplates`, `hasSeenStarterTemplatesNote` and `hasSeededStreakHistory`,
    /// which are one-time flags. Restoring them would be wrong or pointless: the starter-template
    /// seeding has already run by the time anyone restores, the note is harmless to see again, and
    /// the streak re-seed merges. Also not carried: the Blockey calendar's identifier, which is
    /// specific to the device's calendar store.
    struct Settings: Codable, Equatable {
        var dayStartMinute: Int?
        var dayEndMinute: Int?
        var snapMinutes: Int?
        var hiddenCalendarIDs: [String]?
        var alarmEnabled: Bool?
        var alarmMinutesBefore: Int?
        var skipPlanPreview: Bool?
    }

    struct Task: Codable {
        var title: String
        var estimatedMinutes: Int
        var category: String
        var sortIndex: Int
        /// Optional so a backup written before this field existed still decodes. Present only
        /// for a task that fell out of a template; restoring it also restores the "from
        /// Workday" note in the inbox.
        var droppedFromTemplateName: String?
        /// Independent of the name, because a task made before names existed was dropped but
        /// has none. Optional so older backups still decode.
        var droppedFromTemplate: Bool?
    }

    struct Template: Codable {
        var id: UUID
        var name: String
        var rows: [Row]

        struct Row: Codable {
            var title: String
            var startMinuteOfDay: Int
            var durationMinutes: Int
            var category: String
        }
    }

    struct Assignment: Codable {
        var weekday: Int
        var templateID: UUID?
    }

    // MARK: Capture

    static func capture(context: ModelContext, defaults: UserDefaults = .standard) throws -> BlockeyBackup {
        var backup = BlockeyBackup()

        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        backup.tasks = tasks.filter { !$0.isDone }.map {
            Task(title: $0.title,
                 estimatedMinutes: $0.estimatedMinutes,
                 category: $0.categoryRaw,
                 sortIndex: $0.sortIndex,
                 droppedFromTemplateName: $0.droppedFromTemplate ? $0.droppedFromTemplateName : nil,
                 droppedFromTemplate: $0.droppedFromTemplate)
        }

        let templates = try context.fetch(FetchDescriptor<DayTemplate>())
        backup.templates = templates.map { template in
            Template(id: template.id,
                     name: template.name,
                     rows: template.orderedRows.map {
                         Template.Row(title: $0.title,
                                      startMinuteOfDay: $0.startMinuteOfDay,
                                      durationMinutes: $0.durationMinutes,
                                      category: $0.categoryRaw)
                     })
        }

        let assignments = try context.fetch(FetchDescriptor<TemplateAssignment>())
        backup.assignments = assignments.map { Assignment(weekday: $0.weekday, templateID: $0.templateID) }

        let activity = try context.fetch(FetchDescriptor<ActivityDay>())
        backup.activityDays = activity.map(\.key).sorted()

        let definitions = try context.fetch(FetchDescriptor<CategoryDefinition>())
        backup.categories = definitions.sorted { ($0.sortIndex, $0.slug) < ($1.sortIndex, $1.slug) }.map {
            Category(slug: $0.slug, name: $0.name, emoji: $0.emoji, symbolName: $0.symbolName,
                     paletteIndex: $0.paletteIndex, sortIndex: $0.sortIndex,
                     archivedAt: $0.archivedAt, customColorHex: $0.customColorHex)
        }

        backup.settings = Settings.read(from: defaults)
        return backup
    }

    // MARK: Decode

    /// Why a file was refused. The message is shown to the user as is.
    enum BackupError: Error, LocalizedError, Equatable {
        case newerVersion(Int)

        var errorDescription: String? {
            "This backup is from a newer version of Blockey. Update the app, then try again."
        }
    }

    /// Decodes a backup, refusing a newer version before reading the rest. The version is read on
    /// its own first because a newer file may not match this build's shape, and a decode error
    /// would then say "not a backup" about a file that is one.
    static func decode(_ data: Data) throws -> BlockeyBackup {
        struct VersionProbe: Decodable { var version: Int }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let probe = try? decoder.decode(VersionProbe.self, from: data), probe.version > currentVersion {
            throw BackupError.newerVersion(probe.version)
        }
        return try decoder.decode(BlockeyBackup.self, from: data)
    }

    // MARK: Validate

    /// Exactly what a restore will do, worked out without touching any store. `restore(into:)`
    /// builds this before its first delete, so a file that cannot be restored fails while the
    /// phone is still untouched.
    struct RestorePlan: Equatable {
        /// Valid definitions, first occurrence of each slug, hex canonicalised.
        var categories: [CategoryDefinitionValue] = []
        /// Entries dropped because their slug repeated an earlier one in the file, or was blank.
        var categoriesSkipped = 0
        /// Only the settings that survived validation.
        var settings = Settings()
    }

    func validated() throws -> RestorePlan {
        guard version <= Self.currentVersion else { throw BackupError.newerVersion(version) }

        var plan = RestorePlan()
        var seen = Set<String>()
        for entry in categories ?? [] {
            // Slugs are kept verbatim (calendar events reference them), but a blank one can never
            // match a token and a repeat would make the merge order-dependent: first wins.
            guard !entry.slug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seen.insert(entry.slug).inserted else {
                plan.categoriesSkipped += 1
                continue
            }
            plan.categories.append(CategoryDefinitionValue(
                slug: entry.slug, name: entry.name, emoji: entry.emoji, symbolName: entry.symbolName,
                paletteIndex: entry.paletteIndex,
                // Unlike a slug, nothing outside the app references a colour, so a bad one is
                // dropped rather than kept.
                customColorHex: entry.customColorHex.flatMap(CategoryCatalog.canonicalHex),
                sortIndex: entry.sortIndex, archivedAt: entry.archivedAt))
        }

        if let s = settings {
            // The window is one setting in two parts. A lone half cannot be checked against the
            // other, so it is ignored rather than guessed at.
            if let start = s.dayStartMinute, let end = s.dayEndMinute,
               (0...1440).contains(start), (0...1440).contains(end), start < end {
                plan.settings.dayStartMinute = start
                plan.settings.dayEndMinute = end
            }
            if let snap = s.snapMinutes, [5, 10, 15, 30].contains(snap) { plan.settings.snapMinutes = snap }
            if let ids = s.hiddenCalendarIDs {
                // Stored newline-joined, so an empty or newline-bearing ID cannot round-trip.
                // Unknown IDs are kept: the set is only used for membership, so they hide nothing.
                plan.settings.hiddenCalendarIDs = ids.filter { !$0.isEmpty && !$0.contains("\n") }
            }
            plan.settings.alarmEnabled = s.alarmEnabled
            plan.settings.alarmMinutesBefore = s.alarmMinutesBefore.map { min(max($0, 0), 60) }
            plan.settings.skipPlanPreview = s.skipPlanPreview
        }
        return plan
    }

    /// How many categories a restore would add or update. Used by the confirmation warning.
    var categoryCount: Int { (try? validated().categories.count) ?? 0 }

    // MARK: Restore

    /// Replaces everything currently stored, except streak days, which are merged.
    ///
    /// Replace rather than merge, deliberately: merging would silently
    /// duplicate every template on a second import, and "restore my backup"
    /// means the state in the file, not the union of two states.
    ///
    /// Categories are the one exception to replace (ADR 005): each is upserted by slug and none is
    /// deleted, because calendar events outside this file point at them. Settings are written to
    /// `defaults` only after the save succeeds, so a failed restore changes nothing.
    @discardableResult
    func restore(into context: ModelContext,
                 defaults: UserDefaults = .standard) throws -> (tasks: Int, templates: Int, categories: Int) {
        // Validate before the first delete.
        let plan = try validated()

        for task in try context.fetch(FetchDescriptor<TaskItem>()) { context.delete(task) }
        for template in try context.fetch(FetchDescriptor<DayTemplate>()) { context.delete(template) }
        for assignment in try context.fetch(FetchDescriptor<TemplateAssignment>()) { context.delete(assignment) }

        for task in tasks {
            context.insert(TaskItem(title: task.title,
                                    estimatedMinutes: task.estimatedMinutes,
                                    categoryRaw: task.category,
                                    sortIndex: task.sortIndex,
                                    droppedFromTemplate: task.droppedFromTemplate ?? (task.droppedFromTemplateName != nil),
                                    droppedFromTemplateName: task.droppedFromTemplateName))
        }

        // Templates keep their identifiers so weekday assignments still resolve.
        for payload in templates {
            let template = DayTemplate(name: payload.name)
            template.id = payload.id
            context.insert(template)
            for rowPayload in payload.rows {
                let row = TemplateRow(title: rowPayload.title,
                                      startMinuteOfDay: rowPayload.startMinuteOfDay,
                                      durationMinutes: rowPayload.durationMinutes,
                                      categoryRaw: rowPayload.category)
                row.template = template
                context.insert(row)
            }
        }

        for assignment in assignments {
            context.insert(TemplateAssignment(weekday: assignment.weekday, templateID: assignment.templateID))
        }

        // Merge, never replace, and ignore a key that is not a real day. Unlike everything above,
        // streak days are not "the state in the file": losing one to an older backup is a loss.
        let existingDays = Set(try context.fetch(FetchDescriptor<ActivityDay>()).map(\.key))
        // The parsed day's canonical key is stored, never the raw string.
        let incoming = Set((activityDays ?? []).compactMap { CivilDay(key: $0)?.key })
        for key in incoming where !existingDays.contains(key) {
            context.insert(ActivityDay(key: key, recordedAt: exportedAt))
        }

        let existing = Dictionary(
            try context.fetch(FetchDescriptor<CategoryDefinition>()).map { ($0.slug, $0) },
            uniquingKeysWith: { first, _ in first })
        for value in plan.categories {
            if let row = existing[value.slug] {
                row.name = value.name
                row.emoji = value.emoji
                row.symbolName = value.symbolName
                row.paletteIndex = value.paletteIndex
                row.sortIndex = value.sortIndex
                row.customColorHex = value.customColorHex
                row.archivedAt = value.archivedAt
            } else {
                context.insert(CategoryDefinition(value))
            }
        }

        do {
            try context.save()
        } catch {
            // Every task and template was deleted a few lines above and those
            // deletions are still pending. Without this the user is told the
            // restore failed while the next autosave quietly carries out the
            // destruction anyway.
            context.rollback()
            throw error
        }
        plan.settings.write(to: defaults)
        return (tasks.count, templates.count, plan.categories.count)
    }

    var suggestedFilename: String {
        "Blockey-\(exportedAt.formatted(.iso8601.year().month().day())).json"
    }
}

extension BlockeyBackup.Settings {
    /// The effective values, defaults applied, so restoring means "the state in the file" and
    /// does not leave a stale value from the target phone where this one was merely unset.
    static func read(from defaults: UserDefaults) -> BlockeyBackup.Settings {
        func int(_ key: String, _ fallback: Int) -> Int {
            defaults.object(forKey: key) == nil ? fallback : defaults.integer(forKey: key)
        }
        let hidden = (defaults.string(forKey: SettingsKey.hiddenCalendarIDs) ?? "")
            .split(separator: "\n").map(String.init).sorted()
        return BlockeyBackup.Settings(
            dayStartMinute: int(SettingsKey.dayStartMinute, SettingsKey.defaultDayStart),
            dayEndMinute: int(SettingsKey.dayEndMinute, SettingsKey.defaultDayEnd),
            snapMinutes: int(SettingsKey.snapMinutes, SettingsKey.defaultSnap),
            hiddenCalendarIDs: hidden,
            alarmEnabled: defaults.bool(forKey: SettingsKey.alarmEnabled),
            alarmMinutesBefore: int(SettingsKey.alarmMinutesBefore, 5),
            skipPlanPreview: defaults.bool(forKey: SettingsKey.skipPlanPreview))
    }

    /// Writes only the fields present, under the keys `@AppStorage` uses.
    func write(to defaults: UserDefaults) {
        if let dayStartMinute { defaults.set(dayStartMinute, forKey: SettingsKey.dayStartMinute) }
        if let dayEndMinute { defaults.set(dayEndMinute, forKey: SettingsKey.dayEndMinute) }
        if let snapMinutes { defaults.set(snapMinutes, forKey: SettingsKey.snapMinutes) }
        if let hiddenCalendarIDs {
            defaults.set(hiddenCalendarIDs.sorted().joined(separator: "\n"), forKey: SettingsKey.hiddenCalendarIDs)
        }
        if let alarmEnabled { defaults.set(alarmEnabled, forKey: SettingsKey.alarmEnabled) }
        if let alarmMinutesBefore { defaults.set(alarmMinutesBefore, forKey: SettingsKey.alarmMinutesBefore) }
        if let skipPlanPreview { defaults.set(skipPlanPreview, forKey: SettingsKey.skipPlanPreview) }
    }
}

/// A decoded backup waiting on the user's confirmation, and what accepting it costs.
///
/// `restore(into:)` deletes every task, template and weekday assignment before
/// inserting the backup's, and the only thing standing between that and a
/// mis-tap in a file picker is this confirmation — so the warning states the
/// numbers rather than the idea, and names the date the backup was saved, since
/// reaching for last month's file is the way this goes wrong.
struct PendingRestore {
    let backup: BlockeyBackup
    let existingTasks: Int
    let existingTemplates: Int

    var warning: String {
        let saved = backup.exportedAt.formatted(date: .abbreviated, time: .shortened)
        let categories = backup.categoryCount
        let incoming = categories > 0
            ? "\(Self.counted(backup.tasks.count, "task")), \(Self.counted(backup.templates.count, "template")) "
                + "and \(Self.counted(categories, "category", plural: "categories"))"
            : "\(Self.counted(backup.tasks.count, "task")) and \(Self.counted(backup.templates.count, "template"))"
        // Said whenever the file would overwrite preferences, since that is a change the user
        // would not otherwise expect from "tasks and templates".
        let tail = (categories > 0 ? " Categories are added or updated, never deleted." : "")
            + (backup.settings != nil ? " Your settings are restored too." : "")
            + " Your calendar blocks are not affected."

        guard existingTasks + existingTemplates > 0 else {
            return "Saved \(saved). It holds \(incoming).\(tail)"
        }

        let losing = "\(Self.counted(existingTasks, "task")) and \(Self.counted(existingTemplates, "template"))"
        return "Saved \(saved). This deletes the \(losing) on this phone and puts back \(incoming).\(tail)"
    }

    /// "1 task", "4 tasks", "no tasks" — a count the sentence can absorb.
    static func counted(_ n: Int, _ noun: String, plural: String? = nil) -> String {
        let many = plural ?? "\(noun)s"
        switch n {
        case 0:  return "no \(many)"
        case 1:  return "1 \(noun)"
        default: return "\(n) \(many)"
        }
    }
}

/// Wraps a backup so SwiftUI's file exporter and importer can carry it.
struct BackupFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var backup: BlockeyBackup

    init(backup: BlockeyBackup) { self.backup = backup }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        backup = try BlockeyBackup.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return FileWrapper(regularFileWithContents: try encoder.encode(backup))
    }
}
