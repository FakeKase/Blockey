import Testing
import Foundation
@testable import Blockey

@Suite("TitleSuggestions")
struct TitleSuggestionsTests {

    // A fixed instant is fine here: the ranker only does arithmetic on the injected `now`
    // and never reads a calendar, so the Buddhist-calendar trap does not apply.
    let now = TestDates.today()

    func day(_ ago: Double) -> Date { now.addingTimeInterval(-ago * 86_400) }

    func sample(_ title: String, _ minutes: Int = 30, slug: String? = nil, daysAgo: Double = 1) -> TitleSample {
        TitleSample(title: title, minutes: minutes, categorySlug: slug, date: day(daysAgo))
    }

    func template(_ title: String, _ minutes: Int = 30, slug: String? = nil) -> TitleSample {
        TitleSample(title: title, minutes: minutes, categorySlug: slug, date: nil)
    }

    func suggest(_ query: String, history: [TitleSample] = [], templates: [TitleSample] = [],
                 known: Set<String> = ["deep", "rest", "health"], limit: Int = 3) -> [TitleSuggestion] {
        TitleSuggestions.suggest(query: query, history: history, templates: templates,
                                 knownSlugs: known, now: now, limit: limit)
    }

    func titles(_ r: [TitleSuggestion]) -> [String] { r.map(\.title) }

    @Test func thaiPartialClusterMatches() {
        let eat = "\u{0E01}\u{0E34}\u{0E19}\u{0E02}\u{0E49}\u{0E32}\u{0E27}"   // กินข้าว
        // "ก" alone is the first half of the cluster "กิ"; String.hasPrefix would say no.
        #expect(titles(suggest("\u{0E01}", history: [sample(eat)])) == [eat])
    }

    @Test func substringMatchesThaiMidWord() {
        let eat = "\u{0E01}\u{0E34}\u{0E19}\u{0E02}\u{0E49}\u{0E32}\u{0E27}"
        #expect(titles(suggest("\u{0E02}\u{0E49}\u{0E32}", history: [sample(eat)])) == [eat])
    }

    @Test func loneCombiningMarkQueryMatchesNothingSpurious() {
        let eat = "\u{0E01}\u{0E34}\u{0E19}"
        #expect(suggest("\u{0E34}", history: [sample(eat)]).isEmpty)
        #expect(suggest("\u{0E49}", history: [sample("\u{0E02}\u{0E49}\u{0E32}\u{0E27}")]).isEmpty)
    }

    @Test func nonInitialThaiVowelQueryMatchesNothing() {
        let h = [sample("\u{0E01}\u{0E32}\u{0E41}\u{0E1F}"), sample("\u{0E19}\u{0E33}")]
        for v in ["\u{0E30}", "\u{0E32}", "\u{0E33}", "\u{0E45}", "\u{0E4D}"] {
            #expect(suggest(v, history: h).isEmpty)
        }
        // Leading vowels start syllables and stay valid.
        let cafe = "\u{0E40}\u{0E01}\u{0E21}"   // เกม
        #expect(titles(suggest("\u{0E40}", history: [sample(cafe)])) == [cafe])
    }

    @Test func exactBeatsPrefixBeatsWordPrefixBeatsSubstring() {
        // Recency runs the opposite way, so only match quality can produce this order.
        let h = [sample("gym", daysAgo: 60),
                 sample("gym bag", daysAgo: 30),
                 sample("the gym", daysAgo: 5),
                 sample("energym", daysAgo: 1)]
        #expect(titles(suggest("gym", history: h, limit: 10)) == ["gym", "gym bag", "the gym", "energym"])
    }

    @Test func recentOutranksOldFrequent() {
        let old = (0..<5).map { _ in sample("Write report", daysAgo: 90) }
        let h = old + [sample("Write email", daysAgo: 1)]
        #expect(titles(suggest("write", history: h)) == ["Write email", "Write report"])
    }

    @Test func recencyUsesInjectedNow() {
        // Template-only "Plan tmpl" scores a fixed 0.5. History from 20 days ago scores ~0.37 at
        // `now`, so the template leads; with "now" moved back 20 days the same sample is brand
        // new (1.0) and leads instead. Only an injected clock can make the order change.
        let h = [sample("Plan hist", daysAgo: 20)]
        let t = [template("Plan tmpl")]
        #expect(titles(suggest("plan", history: h, templates: t)) == ["Plan tmpl", "Plan hist"])
        let earlier = now.addingTimeInterval(-20 * 86_400)
        let r = TitleSuggestions.suggest(query: "plan", history: h, templates: t, knownSlugs: [],
                                         now: earlier, limit: 3)
        #expect(titles(r) == ["Plan hist", "Plan tmpl"])
    }

    @Test func dedupesVariantsShowingLatestSpelling() {
        let h = [sample("call mom", daysAgo: 9), sample("CALL  MOM", daysAgo: 3), sample("Call Mom ", daysAgo: 1)]
        let r = suggest("call", history: h)
        #expect(titles(r) == ["Call Mom"])
        // A different spelling that is older must not win even if it appears later in the array.
        let h2 = [sample("Call Mom", daysAgo: 1), sample("call mom", daysAgo: 9)]
        #expect(titles(suggest("call", history: h2)) == ["Call Mom"])
    }

    @Test func callMomAndCallTomStaySeparateInResults() {
        let r = suggest("call", history: [sample("Call mom"), sample("Call Tom")])
        #expect(Set(titles(r)) == ["Call mom", "Call Tom"])
    }

    @Test func tieBreakIsDeterministic() {
        let a = [sample("Plan b"), sample("Plan a"), sample("Plan c")]
        let expected = ["Plan a", "Plan b", "Plan c"]
        #expect(titles(suggest("plan", history: a)) == expected)
        #expect(titles(suggest("plan", history: a.reversed())) == expected)
    }

    @Test func remembersLatestMinutesAndSlug() {
        let h = [sample("Gym", 45, slug: "rest", daysAgo: 10), sample("gym", 60, slug: "health", daysAgo: 2)]
        let r = suggest("gy", history: h)
        #expect(r.first?.minutes == 60)
        #expect(r.first?.categorySlug == "health")
    }

    @Test func nonPresetDurationSurvives() {
        #expect(suggest("gym", history: [sample("Gym", 50)]).first?.minutes == 50)
    }

    @Test func unknownOrArchivedSlugIsNotRestored() {
        let h = [sample("Gym", 45, slug: "archived-thing")]
        let r = suggest("gym", history: h)
        #expect(r.count == 1)
        #expect(r.first?.categorySlug == nil)
        #expect(r.first?.minutes == 45)
        #expect(suggest("gym", history: [sample("Gym", slug: "health")], known: []).first?.categorySlug == nil)
    }

    @Test func templateRowsCountWithoutDate() {
        // A template-only key scores like one use 14 days ago (0.5): above 30 days ago, below 5.
        let t = [template("Plan tmpl")]
        let h = [sample("Plan newer", daysAgo: 5), sample("Plan older", daysAgo: 30)]
        #expect(titles(suggest("plan", history: h, templates: t)) == ["Plan newer", "Plan tmpl", "Plan older"])
    }

    @Test func templateRowSameKeyAsHistoryDoesNotDoubleCount() {
        // If the template row were added to the history score, "Gym" (30 days ago + template)
        // would beat "Gyro" (14 days ago, 0.5). Alone, 30 days is about 0.23.
        let h = [sample("Gym", daysAgo: 30), sample("Gyro", daysAgo: 14)]
        let t = [template("GYM", 60, slug: "health")]
        let r = suggest("gy", history: h, templates: t)
        #expect(titles(r) == ["Gyro", "Gym"])
        // And the history spelling and minutes win over the template's.
        #expect(r.last?.minutes == 30)
    }

    @Test func exactTypedMatchStillOffered() {
        #expect(titles(suggest("Gym", history: [sample("gym", 45)])) == ["gym"])
    }

    @Test func emptyOrWhitespaceQueryReturnsNothing() {
        let h = [sample("Gym")]
        #expect(suggest("", history: h).isEmpty)
        #expect(suggest("   \n", history: h).isEmpty)
        #expect(suggest("\u{200B}", history: h).isEmpty)
    }

    @Test func emptyHistoryNoTemplatesReturnsNothing() {
        #expect(suggest("gym").isEmpty)
    }

    @Test func templatesOnlyHistoryStillSuggests() {
        let r = suggest("lun", templates: [template("Lunch", 45, slug: "rest")])
        #expect(titles(r) == ["Lunch"])
        #expect(r.first?.minutes == 45)
        #expect(r.first?.categorySlug == "rest")
    }

    @Test func defaultNewBlockTitleIsExcluded() {
        #expect(DefaultTitles.newBlock == "New block")
        let h = [sample("New block"), sample("  NEW  block "), sample("New plan")]
        #expect(titles(suggest("new", history: h, templates: [template("New block")])) == ["New plan"])
        #expect(suggest("n", templates: [template("New block")]).isEmpty)
    }

    @Test func longTitlesMatchWithinBudget() {
        let filler = String(repeating: "lorem ipsum dolor ", count: 28)   // about 500 characters
        let h = (0..<2000).map { sample("\(filler)\($0)", daysAgo: Double($0 % 90)) }
        let start = Date()
        let r = suggest("dolor 19", history: h)
        let elapsed = Date().timeIntervalSince(start)
        #expect(!r.isEmpty)
        // Generous for a Debug build on a loaded simulator; the real cost is a fraction of this.
        #expect(elapsed < 2.0, "took \(elapsed)s")
    }

    @Test func respectsLimits() {
        let h = (0..<10).map { sample("Task \($0)", daysAgo: Double($0)) }
        #expect(suggest("task", history: h).count == 3)
        #expect(suggest("task", history: h, limit: 5).count == 5)
        #expect(suggest("task", history: h, limit: 0).isEmpty)
        #expect(suggest("task", history: h, limit: 50).count == 10)
    }
}
