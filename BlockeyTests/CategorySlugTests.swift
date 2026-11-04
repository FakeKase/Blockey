import Testing
import Foundation
@testable import Blockey

/// Plan Appendix A.4, CategorySlug (task 3.1). Thai strings are written as escapes where the exact
/// scalars matter, because an editor can silently renormalise a literal.
@Suite("CategorySlug")
struct CategorySlugTests {

    /// A fixed-sequence generator so the random-slug test is deterministic. `next()` walks a
    /// counter, and `Int.random(in:using:)` maps it onto the alphabet.
    private struct Counting: RandomNumberGenerator {
        var n: UInt64 = 0
        mutating func next() -> UInt64 { defer { n &+= 0x9E37_79B9_7F4A_7C15 }; return n }
    }

    private func mint(_ name: String, taken: Set<String> = []) -> String? {
        var rng = Counting()
        return CategorySlug.mint(name: name, taken: taken, random: &rng)
    }

    // Thai: ง า น บ + MAI THO + า น
    private let thaiHouseWork = "\u{0E07}\u{0E32}\u{0E19}\u{0E1A}\u{0E49}\u{0E32}\u{0E19}"

    @Test func mintPrefixesCustomSlugs() {
        #expect(mint("Reading") == "u-reading")
    }

    @Test func mintKeepsThaiCombiningMarks() {
        #expect(mint(thaiHouseWork) == "u-" + thaiHouseWork)
        // Rice and white differ only by vowel and tone marks; folding the marks would merge them.
        let rice = mint("\u{0E02}\u{0E49}\u{0E32}\u{0E27}")
        let white = mint("\u{0E02}\u{0E32}\u{0E27}")
        #expect(rice != white)
        #expect(rice == "u-\u{0E02}\u{0E49}\u{0E32}\u{0E27}")
    }

    @Test func mintLowercasesLatinAndDashesPunctuation() {
        #expect(mint("Deep  Work!!") == "u-deep-work")
        #expect(mint("  --Gym / Run--  ") == "u-gym-run")
        #expect(mint("Café 2") == "u-café-2")
    }

    @Test func fullWidthLatinNameSlugsToAscii() {
        #expect(mint("\u{FF27}\u{FF59}\u{FF4D}") == "u-gym")
    }

    @Test func slugFromNfdAndNfcNameIsIdentical() {
        let nfc = "caf\u{00E9}"
        let nfd = "cafe\u{0301}"
        #expect(nfc != nfd || nfc.unicodeScalars.count != nfd.unicodeScalars.count)
        #expect(mint(nfc) == mint(nfd))
        #expect(mint(nfc)?.unicodeScalars.contains("\u{0301}") == false)
    }

    @Test func sarAmAndItsDecompositionMintTheSameSlug() {
        // U+0E33 decomposes to U+0E4D U+0E32 under NFKC (ADR 005, "Slugs").
        #expect(mint("\u{0E19}\u{0E33}") == mint("\u{0E19}\u{0E4D}\u{0E32}"))
    }

    @Test func mintAppendsSuffixOnCollision() {
        #expect(mint("Gym", taken: ["u-gym"]) == "u-gym-2")
        #expect(mint("Gym", taken: ["u-gym", "u-gym-2"]) == "u-gym-3")
    }

    @Test func mintCollidesWithArchivedSlugs() {
        // `taken` is the catalog's every slug, archived included; the minter just honours it.
        let catalog = CategoryCatalog(definitions: [
            .fixture(slug: "u-gym", name: "Gym", archivedAt: TestDates.today())
        ], paletteCount: 12)
        #expect(mint("Gym", taken: catalog.takenSlugs) == "u-gym-2")
    }

    @Test func renameDoesNotChangeSlug() {
        // A rename edits the definition's name only. The slug is minted once and nothing in the
        // minter or the value type derives it again.
        var def = CategoryDefinitionValue.fixture(slug: "u-gym", name: "Gym")
        let slug = def.slug
        def.name = "Training"
        #expect(def.slug == slug)
    }

    @Test func emojiOnlyNameGetsRandomSlug() throws {
        let slug = try #require(mint("\u{1F3CB}\u{FE0F}\u{1F525}"))
        #expect(slug.hasPrefix("u-"))
        let body = slug.dropFirst(2)
        #expect(body.count == 6)
        #expect(body.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) })
        // Same injected source, same slug.
        #expect(mint("\u{1F3CB}\u{FE0F}\u{1F525}") == slug)
    }

    @Test func randomSlugAlsoSuffixesOnCollision() throws {
        let first = try #require(mint("\u{1F525}"))
        #expect(mint("\u{1F525}", taken: [first]) == first + "-2")
    }

    @Test func mintCapsAt32WithoutSplittingAThaiCluster() throws {
        let latin = try #require(mint(String(repeating: "a", count: 50)))
        #expect(latin == "u-" + String(repeating: "a", count: 32))

        // 31 plain consonants then BO BAIMAI + MAI THO: the 32nd cluster is the consonant with its
        // tone mark, which must stay together or be dropped whole.
        let thai = String(repeating: "\u{0E01}", count: 31) + "\u{0E1A}\u{0E49}" + "\u{0E01}"
        let slug = try #require(mint(thai))
        let body = String(slug.dropFirst(2))
        #expect(body.count == 32)
        #expect(body.hasSuffix("\u{0E1A}\u{0E49}"))

        // At 32 exactly, the mark's base is the 32nd cluster; one more pushes the whole cluster out.
        let pushed = String(repeating: "\u{0E01}", count: 32) + "\u{0E1A}\u{0E49}"
        let pushedBody = String(try #require(mint(pushed)).dropFirst(2))
        #expect(pushedBody == String(repeating: "\u{0E01}", count: 32))
    }

    @Test func capDoesNotLeaveATrailingDash() throws {
        let name = String(repeating: "a", count: 31) + " bbb"
        #expect(mint(name) == "u-" + String(repeating: "a", count: 31))
    }

    @Test func suffixIsAppendedAfterTheCap() throws {
        let long = String(repeating: "a", count: 50)
        let first = "u-" + String(repeating: "a", count: 32)
        #expect(mint(long, taken: [first]) == first + "-2")
    }

    @Test func emptyWhitespaceOrZeroWidthNameIsRejected() {
        #expect(mint("") == nil)
        #expect(mint("   \n\t") == nil)
        #expect(mint("\u{200B}\u{200C}\u{200D}\u{2060}\u{FEFF}") == nil)
        #expect(mint(" \u{200B} ") == nil)
    }

    @Test func builtInSlugsAreNeverMintable() {
        for name in ["deep", "Meeting", "ADMIN", "personal", "Health", "rest"] {
            let slug = mint(name)
            #expect(slug?.hasPrefix("u-") == true)
            #expect(slug.map { !CategoryCatalog.builtInSlugs.contains($0) } == true)
        }
    }

    @Test func displayNameFromSlugIsBestEffort() {
        #expect(CategorySlug.displayName(fromSlug: "u-deep-work") == "deep work")
        #expect(CategorySlug.displayName(fromSlug: "u-" + thaiHouseWork) == thaiHouseWork)
        #expect(CategorySlug.displayName(fromSlug: "u-gym-2") == "gym 2")   // suffix is not recoverable
        #expect(CategorySlug.displayName(fromSlug: "mystery") == "mystery")  // no prefix to drop
        #expect(CategorySlug.displayName(fromSlug: "u-") == "u-")            // nothing left, show the slug
    }

    // MARK: FNV-1a

    @Test func fnv1aMatchesPublishedVectors() {
        #expect(CategorySlug.fnv1a32("") == 0x811C_9DC5)
        #expect(CategorySlug.fnv1a32("a") == 0xE40C_292C)
        #expect(CategorySlug.fnv1a32("foobar") == 0xBF9C_F968)
    }

    @Test func unknownSlugIndexMatchesHardCodedValue() {
        // Catches anyone "simplifying" this to hashValue, which is seeded per process.
        #expect(CategorySlug.fnv1a32("u-reading") == 0xA69A_0C4D)
        #expect(CategorySlug.standInPaletteIndex(for: "u-reading", paletteCount: 12) == 1)
        #expect(CategorySlug.standInPaletteIndex(for: "u-\u{0E07}\u{0E32}\u{0E19}\u{0E1A}\u{0E49}\u{0E32}\u{0E19}",
                                                 paletteCount: 12) == 8)
        #expect(CategorySlug.standInPaletteIndex(for: "u-gym", paletteCount: 7) == 5)
    }

    @Test func standInIndexSurvivesAHugePaletteCount() {
        let index = CategorySlug.standInPaletteIndex(for: "u-gym", paletteCount: Int.max)
        #expect(index >= 0)
    }

    @Test func standInIndexSurvivesAnEmptyPalette() {
        #expect(CategorySlug.standInPaletteIndex(for: "u-gym", paletteCount: 0) == 0)
    }
}

extension CategoryDefinitionValue {
    /// Test-only builder so each test names just the fields it cares about.
    static func fixture(slug: String, name: String = "Name", emoji: String = "X",
                        symbolName: String = "star", paletteIndex: Int = 0,
                        customColorHex: String? = nil, sortIndex: Int = 100,
                        archivedAt: Date? = nil) -> CategoryDefinitionValue {
        CategoryDefinitionValue(slug: slug, name: name, emoji: emoji, symbolName: symbolName,
                                paletteIndex: paletteIndex, customColorHex: customColorHex,
                                sortIndex: sortIndex, archivedAt: archivedAt)
    }
}
