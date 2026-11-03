import Testing
@testable import Blockey

@Suite struct StreakCopyTests {
    private func summary(_ current: Int, today: Bool = false, risk: Bool = false,
                         broke: Bool = false, longest: Int? = nil) -> StreakSummary {
        StreakSummary(current: current, longest: longest ?? current, isAtRisk: risk,
                      countedToday: today, justBroke: broke)
    }

    @Test func noStreakShowsNothing() {
        #expect(StreakCopy.badge(for: .empty) == nil)
        #expect(StreakCopy.badge(for: summary(0)) == nil)
    }

    @Test func justBrokeShowsNothing() {
        #expect(StreakCopy.badge(for: summary(0, broke: true, longest: 9)) == nil)
    }

    @Test func activeSingularAndPlural() {
        #expect(StreakCopy.badge(for: summary(1, today: true))
                == .active("1-day streak", accessibility: "Streak: 1 day. You have added blocks today."))
        let b = StreakCopy.badge(for: summary(4, today: true))
        #expect(b == .active("4-day streak", accessibility: "Streak: 4 days. You have added blocks today."))
    }

    @Test func atRiskSingularAndPlural() {
        #expect(StreakCopy.badge(for: summary(1, risk: true))
                == .atRisk("Keep your 1-day streak", accessibility: "Streak: 1 day. Add a block today to keep it."))
        let b = StreakCopy.badge(for: summary(3, risk: true))
        #expect(b?.text == "Keep your 3-day streak")
        #expect(b?.accessibility == "Streak: 3 days. Add a block today to keep it.")
    }

    @Test func restartAfterBreakReadsAsOneDay() {
        // First add after a break: counted today, run of 1, best from before.
        #expect(StreakCopy.badge(for: summary(1, today: true, longest: 12))?.text == "1-day streak")
    }

    @Test func bestRow() {
        #expect(StreakCopy.best(0) == "Best: none yet")
        #expect(StreakCopy.best(1) == "Best: 1 day")
        #expect(StreakCopy.best(12) == "Best: 12 days")
    }

    @Test func announcement() {
        #expect(StreakCopy.incrementAnnouncement(4) == "Streak is now 4 days.")
        #expect(StreakCopy.incrementAnnouncement(1) == "Streak is now 1 day.")
    }

    @Test func announcesOnlyOnIncrease() {
        let risk = summary(3, risk: true)
        let counted = summary(4, today: true)
        #expect(!StreakCopy.shouldAnnounce(from: nil, to: counted))      // launch
        #expect(StreakCopy.shouldAnnounce(from: risk, to: counted))      // the add
        #expect(!StreakCopy.shouldAnnounce(from: counted, to: counted))  // second add same day
        #expect(!StreakCopy.shouldAnnounce(from: counted, to: risk))     // never goes down
        #expect(StreakCopy.shouldAnnounce(from: .empty, to: summary(1, today: true)))
    }
}
