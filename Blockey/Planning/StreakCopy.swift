import Foundation

/// The words for the daily streak (issue #7, docs/ui-spec-issue-7.md), kept as pure functions so the
/// views only lay them out and every state's sentence can be tested. Foundation only.
enum StreakCopy {

    /// What the Today header shows for a summary. `nil` means show nothing: no streak yet, or it
    /// just broke (a broken streak is deliberately shown nowhere on Today).
    enum Badge: Equatable {
        case active(String, accessibility: String)
        case atRisk(String, accessibility: String)

        var text: String {
            switch self {
            case .active(let text, _), .atRisk(let text, _): text
            }
        }
        var accessibility: String {
            switch self {
            case .active(_, let label), .atRisk(_, let label): label
            }
        }
    }

    static func days(_ n: Int) -> String { "\(n) day\(n == 1 ? "" : "s")" }

    static func badge(for summary: StreakSummary) -> Badge? {
        let n = summary.current
        guard n >= 1, !summary.justBroke else { return nil }
        if summary.countedToday {
            return .active("\(n)-day streak",
                           accessibility: "Streak: \(days(n)). You have added blocks today.")
        }
        if summary.isAtRisk {
            return .atRisk("Keep your \(n)-day streak",
                           accessibility: "Streak: \(days(n)). Add a block today to keep it.")
        }
        return nil
    }

    /// The Settings row's trailing value.
    static func best(_ longest: Int) -> String {
        longest <= 0 ? "Best: none yet" : "Best: \(days(longest))"
    }

    static let settingsFooter = "Counts each day you add a block. Undo and delete do not remove a day."

    /// Spoken when the count goes up while VoiceOver is running.
    static func incrementAnnouncement(_ n: Int) -> String { "Streak is now \(days(n))." }

    /// Whether to announce: the count rose to a counted day, and it was not the first load (`old` nil).
    static func shouldAnnounce(from old: StreakSummary?, to new: StreakSummary) -> Bool {
        guard let old else { return false }
        return new.countedToday && new.current > old.current
    }
}
