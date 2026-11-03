import Testing
import Foundation
@testable import Blockey

@Suite("Composer suggestion row")
struct ComposerSuggestionRowTests {

    let now = TestDates.today()

    func sample(_ title: String, _ minutes: Int = 30, slug: String? = "deep", daysAgo: Double = 1) -> TitleSample {
        TitleSample(title: title, minutes: minutes, categorySlug: slug,
                    date: now.addingTimeInterval(-daysAgo * 86_400))
    }

    func row(_ history: [TitleSample] = [], templates: [TitleSample] = []) -> ComposerSuggestionRow {
        ComposerSuggestionRow(history: history, templates: templates)
    }

    // MARK: Which chips

    @Test func emptyHistoryShowsNothing() {
        var r = row()
        r.refresh(query: "gym", now: now)
        #expect(r.visibleChips(for: "gym").isEmpty)
    }

    @Test func whitespaceOnlyTextShowsNothingAndDoesNotWaitForDebounce() {
        var r = row([sample("Gym")])
        r.refresh(query: "g", now: now)
        #expect(r.visibleChips(for: "g").count == 1)
        #expect(r.visibleChips(for: "   ").isEmpty)
        #expect(r.visibleChips(for: "").isEmpty)
    }

    @Test func atMostThreeChips() {
        var r = row((1...6).map { sample("Task \($0)") })
        r.refresh(query: "task", now: now)
        #expect(r.visibleChips(for: "task").count == 3)
    }

    @Test func templateRowsAreSuggested() {
        var r = row(templates: [TitleSample(title: "Review inbox", minutes: 20, categorySlug: "admin", date: nil)])
        r.refresh(query: "rev", now: now)
        #expect(r.visibleChips(for: "rev").map(\.title) == ["Review inbox"])
    }

    @Test func defaultNewBlockTitleIsNeverSuggested() {
        var r = row([sample(DefaultTitles.newBlock)])
        r.refresh(query: "new", now: now)
        #expect(r.visibleChips(for: "new").isEmpty)
    }

    // MARK: IME

    @Test func composingKeepsTheCurrentChips() {
        var r = row([sample("Gym"), sample("Call mom")])
        r.refresh(query: "gy", now: now)
        r.refresh(query: "c", isComposing: true, now: now)
        #expect(r.chips.map(\.title) == ["Gym"])
        r.refresh(query: "c", isComposing: false, now: now)
        #expect(r.chips.map(\.title) == ["Call mom"])
    }

    // MARK: Tap

    @Test func tapHidesChipsUntilTheUserTypesAgain() {
        var r = row([sample("Gym"), sample("Gym class")])
        r.refresh(query: "gym", now: now)
        var draft = ComposerDraft()
        draft.apply(r.chips[0])
        r.suppress(forText: draft.title)
        // The refresh the programmatic change triggers must not bring them back.
        r.refresh(query: draft.title, now: now)
        #expect(r.visibleChips(for: draft.title).isEmpty)
        // Typing more: new text, new chips.
        r.refresh(query: "Gym c", now: now)
        #expect(r.visibleChips(for: "Gym c").map(\.title) == ["Gym class"])
    }

    @Test func deletingBackToTheSuppressedTextAfterTypingShowsChipsAgain() {
        var r = row([sample("Gym"), sample("Gym class")])
        r.refresh(query: "gym", now: now)
        r.suppress(forText: "Gym")
        r.refresh(query: "Gym c", now: now)
        r.refresh(query: "Gym", now: now)
        #expect(!r.visibleChips(for: "Gym").isEmpty)
    }

    // MARK: Draft

    @Test func applyFillsTitleDurationAndCategoryWithoutSubmitting() {
        var d = ComposerDraft()
        d.apply(TitleSuggestion(title: "Gym", minutes: 45, categorySlug: "health"))
        #expect(d.title == "Gym")
        #expect(d.minutes == 45)
        #expect(d.category == .health)
        #expect(d.extraMinutes == nil)
    }

    @Test func nonPresetDurationBecomesASelectedExtraChip() {
        var d = ComposerDraft()
        d.apply(TitleSuggestion(title: "Gym", minutes: 50, categorySlug: nil))
        #expect(d.minutes == 50)
        #expect(d.durations == [15, 30, 45, 50, 60, 90, 120])
        d.apply(TitleSuggestion(title: "Gym", minutes: 60, categorySlug: nil))
        #expect(d.durations == ComposerDraft.presetDurations)
    }

    @Test func nilOrUnknownSlugLeavesTheCategoryAlone() {
        var d = ComposerDraft()
        d.category = .rest
        d.apply(TitleSuggestion(title: "Gym", minutes: 30, categorySlug: nil))
        #expect(d.category == .rest)
        d.apply(TitleSuggestion(title: "Gym", minutes: 30, categorySlug: "not-a-slug"))
        #expect(d.category == .rest)
    }

    @Test func applyCapsAndFlattensTheTitle() {
        var d = ComposerDraft()
        d.apply(TitleSuggestion(title: String(repeating: "x", count: 300), minutes: 30, categorySlug: nil))
        #expect(d.title.count == ComposerTitle.maxLength)
    }

    @Test func resetKeepsASelectedExtraDurationOnly() {
        var d = ComposerDraft()
        d.apply(TitleSuggestion(title: "Gym", minutes: 50, categorySlug: nil))
        d.resetTitle()
        #expect(d.title.isEmpty && d.minutes == 50 && d.durations.contains(50))
        d.minutes = 30
        d.resetTitle()
        #expect(d.durations == ComposerDraft.presetDurations)
    }

    // MARK: Chip text

    @Test func visibleTextEndsWithTheDuration() {
        let s = TitleSuggestion(title: "Gym", minutes: 45, categorySlug: "health")
        #expect(SuggestionChipText.visible(s) == "Gym \u{00B7} 45m")
        #expect(SuggestionChipText.duration(90) == "1.5h")
        #expect(SuggestionChipText.duration(120) == "2h")
    }

    @Test func accessibilityLabelHasFullTitleDurationAndCategory() {
        let long = String(repeating: "a", count: 120)
        let s = TitleSuggestion(title: long, minutes: 45, categorySlug: "health")
        #expect(SuggestionChipText.accessibilityLabel(s) == "\(long), 45 minutes, Health")
        let noCategory = TitleSuggestion(title: "Gym", minutes: 45, categorySlug: nil)
        #expect(SuggestionChipText.accessibilityLabel(noCategory) == "Gym, 45 minutes")
    }

    @Test func debounceIsAboutAQuarterSecond() {
        #expect(ComposerSuggestionRow.debounce == .milliseconds(250))
    }

    // MARK: QA additions (task 4.5 review)

    @Test func capNeverSplitsAThaiClusterAndMatchesTheSubmitCap() {
        // "ก็" is two scalars, one Character. 199 + the pair must cap by Character, as the
        // view's onChange does with prefix(maxLength), and agree with ComposerTitle.forSubmit.
        let raw = String(repeating: "a", count: 199) + "ก็" + "ข"
        let capped = String(raw.prefix(ComposerTitle.maxLength))
        #expect(capped.count == ComposerTitle.maxLength)
        #expect(capped.hasSuffix("ก็"))
        #expect(ComposerTitle.forSubmit(raw) == capped)
    }

    @Test func tappingTheSuggestionThatMatchesTheTypedTextStillSuppressesChips() {
        var r = row([sample("Gym", 45, slug: "health")])
        r.refresh(query: "Gym", now: now)
        var d = ComposerDraft()
        d.title = "Gym"
        d.apply(r.chips[0])
        r.suppress(forText: d.title)
        r.refresh(query: d.title, now: now)   // the debounce firing after the tap
        #expect(r.visibleChips(for: d.title).isEmpty)
        #expect(d.minutes == 45 && d.category == .health)
    }

    @Test func extraChipFromAnEarlierTapDoesNotChangeTheSubmittedMinutes() {
        var d = ComposerDraft()
        d.apply(TitleSuggestion(title: "Gym", minutes: 50, categorySlug: nil))
        d.minutes = 30                       // user taps the 30m preset
        d.resetTitle()                       // after Add
        #expect(d.minutes == 30)
        #expect(d.extraMinutes == nil)
    }

    // MARK: Review fixes

    @Test func chipsHideAtOnceWhenTheTextNoLongerMatchesThem() {
        var r = row([sample("Gym")])
        r.refresh(query: "gym", now: now)
        #expect(r.visibleChips(for: "gym").count == 1)
        #expect(r.visibleChips(for: "gymx").isEmpty)
        #expect(r.visibleChips(for: "GYM").count == 1)
    }

    @Test func staleChipsStayForTextTheyStillMatch() {
        var r = row([sample("Gym class")])
        r.refresh(query: "gym", now: now)
        #expect(r.visibleChips(for: "gym c").count == 1)
    }

    @Test func thaiPartialClusterStillMatchesStaleChip() {
        var r = row([sample("\u{0E01}\u{0E34}\u{0E19}\u{0E02}\u{0E49}\u{0E32}\u{0E27}")])
        r.refresh(query: "\u{0E01}", now: now)
        #expect(r.visibleChips(for: "\u{0E01}\u{0E34}\u{0E19}").count == 1)
    }

    @Test func submitClearsChipsSoTheNextKeystrokeShowsNone() {
        var r = row([sample("Gym"), sample("Run")])
        r.refresh(query: "g", now: now)
        r.clear()
        #expect(r.visibleChips(for: "r").isEmpty)
        #expect(r.visibleChips(for: "g").isEmpty)
    }

    @Test func selectingAnotherPresetDropsTheExtraChip() {
        var d = ComposerDraft()
        d.apply(TitleSuggestion(title: "Gym", minutes: 50, categorySlug: nil))
        d.select(minutes: 50)
        #expect(d.durations.contains(50))
        d.select(minutes: 60)
        #expect(d.minutes == 60)
        #expect(d.durations == ComposerDraft.presetDurations)
    }
}
