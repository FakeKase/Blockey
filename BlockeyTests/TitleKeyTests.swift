import Testing
import Foundation
@testable import Blockey

/// Plan Appendix A.6. Thai strings are written as escapes where the exact scalars matter, because
/// an editor can silently renormalise a literal and turn the test into a different test.
@Suite("TitleKey")
struct TitleKeyTests {

    @Test func trimsAndCollapsesWhitespaceNewlinesAndTabs() {
        #expect(TitleKey.normalize("  Call \t\n  mom \r\n") == "call mom")
        #expect(TitleKey.normalize("a\u{00A0}\u{3000}b") == "a b")
        #expect(TitleKey.normalize("   \n\t ") == "")
    }

    @Test func foldsCaseAndWidthLocaleIndependently() {
        #expect(TitleKey.normalize("CALL Mom") == TitleKey.normalize("call mom"))
        // Full-width Latin and a half-width katakana both fold to their plain forms.
        #expect(TitleKey.normalize("Ｃａｌｌ　ｍｏｍ") == "call mom")
        #expect(TitleKey.normalize("ﾃｽﾄ") == TitleKey.normalize("テスト"))
        // Turkish dotless/dotted I must not depend on the phone's region.
        #expect(TitleKey.normalize("TITLE") == "title")
    }

    @Test func nfcAndNfdAreSameKey() {
        #expect(TitleKey.normalize("caf\u{00E9}") == TitleKey.normalize("cafe\u{0301}"))
    }

    @Test func thaiSaraAmComposedAndDecomposedMatch() {
        // U+0E33 SARA AM versus U+0E4D U+0E32 (NIKHAHIT + SARA AA).
        #expect(TitleKey.normalize("\u{0E19}\u{0E33}") == TitleKey.normalize("\u{0E19}\u{0E4D}\u{0E32}"))
    }

    @Test func stripsZwspAndBomKeepsZwj() {
        #expect(TitleKey.normalize("ca\u{200B}ll\u{FEFF} mom") == "call mom")
        let family = "\u{1F468}\u{200D}\u{1F469}"
        #expect(TitleKey.normalize(family).unicodeScalars.contains("\u{200D}"))
    }

    @Test func keepsThaiToneMarks() {
        let rice = "\u{0E02}\u{0E49}\u{0E32}\u{0E27}"   // ข้าว
        let white = "\u{0E02}\u{0E32}\u{0E27}"          // ขาว
        #expect(TitleKey.normalize(rice) != TitleKey.normalize(white))
        #expect(TitleKey.normalize(rice) == rice)
    }

    @Test func trailingPunctuationIsADifferentKey() {
        #expect(TitleKey.normalize("Gym") != TitleKey.normalize("Gym."))
    }

    @Test func callMomAndCallTomStaySeparate() {
        #expect(TitleKey.normalize("Call mom") != TitleKey.normalize("Call Tom"))
    }
}

@Suite("ComposerTitle")
struct ComposerTitleTests {

    @Test func pastedNewlinesBecomeSpaces() {
        #expect(ComposerTitle.forSubmit("one\ntwo\r\nthree\rfour\u{2028}five") == "one two three four five")
        #expect(ComposerTitle.forSubmit("  \n padded \n ") == "padded")
        #expect(ComposerTitle.forSubmit("\n\n") == "")
    }

    @Test func titleCappedAt200() {
        let long = String(repeating: "a", count: 500)
        #expect(ComposerTitle.forSubmit(long).count == 200)
        #expect(ComposerTitle.forSubmit(String(repeating: "b", count: 200)).count == 200)
        // The cap counts characters, so it never splits a Thai cluster or an emoji.
        let thai = String(repeating: "\u{0E01}\u{0E34}", count: 300)
        #expect(ComposerTitle.forSubmit(thai).count == 200)
        #expect(ComposerTitle.forSubmit(thai).unicodeScalars.count == 400)
        // Cutting after a space must not leave trailing whitespace.
        let spaced = String(repeating: "a", count: 199) + " bbb"
        #expect(ComposerTitle.forSubmit(spaced) == String(repeating: "a", count: 199))
    }
}
