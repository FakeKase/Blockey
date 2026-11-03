import Foundation
import SwiftData

/// Records and reads the days on which something was added (issue #7). Foundation and SwiftData
/// only. The rules live in `Streak`; this is the storage around them.
///
/// Like `DayPlanner` it saves nothing and leaves persistence to SwiftData's autosave.
@MainActor
struct StreakStore {
    let context: ModelContext
    let calendar: Calendar

    /// Records the day `now` falls on, once. Returns whether a new day was stored.
    ///
    /// `now` is the moment the user acted, never the day the blocks landed on: planning
    /// tomorrow tonight is today's activity.
    @discardableResult
    func record(now: Date) -> Bool {
        insert(CivilDay(now, in: calendar), recordedAt: now)
    }

    /// Adds days not already stored and returns how many were new. Used by the seed and by
    /// restore, which merges rather than replaces.
    @discardableResult
    func merge<S: Sequence>(_ days: S, recordedAt: Date) -> Int where S.Element == CivilDay {
        var added = 0
        for day in days where insert(day, recordedAt: recordedAt) { added += 1 }
        return added
    }

    func days() -> Set<CivilDay> {
        let rows = (try? context.fetch(FetchDescriptor<ActivityDay>())) ?? []
        return Set(rows.compactMap { CivilDay(key: $0.key) })
    }

    /// What the UI calls.
    func summary(now: Date) -> StreakSummary {
        Streak.summary(days: days(), now: now, calendar: calendar)
    }

    // MARK: Seed

    /// Seeds from the creation dates of existing Blockey events, once ever.
    ///
    /// `creationDates` is given the start of the 365-day window and returns the dates, or nil if
    /// the calendar cannot be read yet (no access, or not synced). Nil or empty leaves the flag
    /// unset so a later reload tries again; setting it then would mean history is never counted.
    ///
    /// - Returns: how many days were added, or nil if nothing was seeded this time.
    @discardableResult
    func seedIfNeeded(defaults: UserDefaults = .standard,
                      now: Date,
                      windowDays: Int = 365,
                      creationDates: (Date) -> [Date]?) -> Int? {
        guard !defaults.bool(forKey: SettingsKey.hasSeededStreak) else { return nil }
        let start = calendar.date(byAdding: .day, value: -windowDays, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(-TimeInterval(windowDays) * 86_400)
        // Empty is treated like nil: it cannot be told from a calendar that has not synced yet,
        // and retrying costs one fetch per reload. A user with genuinely no history pays that
        // until their first add, which is cheap and bounded.
        guard let dates = creationDates(start), !dates.isEmpty else { return nil }
        let days = StreakSeed.days(fromCreationDates: dates, now: now, windowDays: windowDays, calendar: calendar)
        let added = merge(days, recordedAt: now)
        defaults.set(true, forKey: SettingsKey.hasSeededStreak)
        return added
    }

    // MARK: Private

    private func insert(_ day: CivilDay, recordedAt: Date) -> Bool {
        let key = day.key
        var existing = FetchDescriptor<ActivityDay>(predicate: #Predicate { $0.key == key })
        existing.fetchLimit = 1
        if let found = try? context.fetch(existing), !found.isEmpty { return false }
        context.insert(ActivityDay(key: key, recordedAt: recordedAt))
        return true
    }
}
