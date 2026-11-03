import Testing
import Foundation
@testable import Blockey

/// QA additions for #2 tasks 4.1 to 4.4: Thai variants a phone keyboard can actually produce.
/// Escapes throughout, so an editor cannot renormalise the scalars.
@Suite("TitleSuggestions Thai QA")
struct TitleSuggestionsThaiQATests {
    let now = TestDates.today()
    func s(_ t: String, ago: Double = 1) -> TitleSample {
        TitleSample(title: t, minutes: 30, categorySlug: nil, date: now.addingTimeInterval(-ago * 86_400))
    }
    func titles(_ q: String, _ h: [TitleSample], templates: [TitleSample] = []) -> [String] {
        TitleSuggestions.suggest(query: q, history: h, templates: templates, knownSlugs: [], now: now).map(\.title)
    }
    let tham = "\u{0E17}\u{0E33}\u{0E07}\u{0E32}\u{0E19}"                 // ทำงาน, composed SARA AM
    let thamDecomposed = "\u{0E17}\u{0E4D}\u{0E32}\u{0E07}\u{0E32}\u{0E19}" // ท + NIKHAHIT + SARA AA

    @Test func decomposedQueryFindsComposedTitle() {
        #expect(titles("\u{0E17}\u{0E4D}\u{0E32}", [s(tham)]) == [tham])
    }
    @Test func composedQueryFindsDecomposedTitle() {
        #expect(titles("\u{0E17}\u{0E33}", [s(thamDecomposed)]) == [thamDecomposed])
    }
    @Test func halfTypedSaraAmQueryMatches() {
        // Just ท + NIKHAHIT, before the user types the SARA AA.
        #expect(titles("\u{0E17}\u{0E4D}", [s(tham)]) == [tham])
    }
    @Test func composedAndDecomposedSpellingsDedupeToLatest() {
        let r = titles("\u{0E17}", [s(tham, ago: 5), s(thamDecomposed, ago: 1)])
        #expect(r == [thamDecomposed])
    }
    @Test func toneMarkQueryDoesNotMatchToneless() {
        let rice = "\u{0E02}\u{0E49}\u{0E32}\u{0E27}", white = "\u{0E02}\u{0E32}\u{0E27}"
        #expect(titles(rice, [s(white)]).isEmpty)
        #expect(titles(white, [s(rice)]).isEmpty)
        #expect(titles("\u{0E02}", [s(rice), s(white)]).count == 2)
    }
    @Test func toneMarkPositionedQueryAfterBaseIsNotFoundWithoutBase() {
        // A query of tone mark + vowel only: first scalar is combining, so nothing.
        #expect(titles("\u{0E49}\u{0E32}", [s("\u{0E02}\u{0E49}\u{0E32}\u{0E27}")]).isEmpty)
    }
    @Test func zeroWidthSpaceInsideTypedQueryIsIgnored() {
        #expect(titles("\u{0E01}\u{200B}\u{0E34}", [s("\u{0E01}\u{0E34}\u{0E19}")]) == ["\u{0E01}\u{0E34}\u{0E19}"])
    }
    @Test func thaiDoesNotMatchUnrelatedThai() {
        #expect(titles("\u{0E01}", [s("\u{0E02}\u{0E49}\u{0E32}\u{0E27}")]).isEmpty)
    }
    @Test func thaiDigitsAreNotFoldedToArabic() {
        #expect(titles("1", [s("\u{0E51} \u{0E04}\u{0E19}")]).isEmpty)
    }
}
