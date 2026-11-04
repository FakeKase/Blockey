import Testing
import Foundation
@testable import Blockey

/// Plan Appendix A.4, CategoryCatalog (task 3.2), over plain values so no test builds a @Model.
/// The palette count is injected; 12 here is a stand-in until the measured palette lands (#12).
@Suite("CategoryCatalog")
struct CategoryCatalogTests {

    private let count = 12
    private func catalog(_ defs: [CategoryDefinitionValue] = []) -> CategoryCatalog {
        CategoryCatalog(definitions: defs, paletteCount: count)
    }
    private var archivedDate: Date { TestDates.today() }

    // MARK: Resolution

    @Test func builtInResolvesWithNoDefinitions() {
        let r = catalog().resolve("meeting")
        #expect(r.slug == "meeting")
        #expect(r.name == "Meeting")
        #expect(r.emoji == "\u{1F465}")
        #expect(r.symbolName == "person.2.fill")
        #expect(r.origin == .builtIn)
        #expect(!r.isArchived)
    }

    @Test func builtInDefaultsMatchTheEnumTheyWereCopiedFrom() {
        // Catalog/ cannot import SwiftUI, so the defaults are a copy of BlockCategory's. This is
        // the tripwire if one is edited without the other.
        let c = catalog()
        for cat in BlockCategory.allCases {
            let r = c.resolve(cat.rawValue)
            #expect(r.name == cat.title)
            #expect(r.emoji == cat.emoji)
            #expect(r.symbolName == cat.symbolName)
        }
    }

    @Test func definitionOverridesBuiltIn() {
        let c = catalog([.fixture(slug: "rest", name: "Nap", emoji: "Z", symbolName: "moon", paletteIndex: 9)])
        let r = c.resolve("rest")
        #expect(r.name == "Nap")
        #expect(r.emoji == "Z")
        #expect(r.symbolName == "moon")
        #expect(r.colorChoice == .palette(9))
        #expect(r.origin == .builtIn)
    }

    @Test func nilSlugResolvesFallback() {
        #expect(catalog().resolve(nil).slug == "deep")
        #expect(catalog().resolve("").slug == "deep")
        #expect(catalog().resolve("  \t").slug == "deep")
    }

    @Test func nilSlugResolvesDeepEvenWhenDeepIsArchived() {
        let c = catalog([.fixture(slug: "deep", name: "Deep work", archivedAt: archivedDate)])
        let r = c.resolve(nil)
        #expect(r.slug == "deep")
        #expect(r.isArchived)
    }

    @Test func customDefinitionResolvesAsCustom() {
        let c = catalog([.fixture(slug: "u-gym", name: "Gym", emoji: "G", paletteIndex: 7)])
        let r = c.resolve("u-gym")
        #expect(r.origin == .custom)
        #expect(r.name == "Gym")
        #expect(r.colorChoice == .palette(7))
    }

    @Test func unknownSlugResolvesStandInWithDerivedName() {
        let r = catalog().resolve("u-deep-reading")
        #expect(r.origin == .standIn)
        #expect(r.slug == "u-deep-reading")
        #expect(r.name == "deep reading")
        #expect(r.emoji == "\u{1F3F7}\u{FE0F}")
        #expect(r.symbolName == "tag")
        #expect(!r.isArchived)
        #expect(r.colorChoice == .palette(CategorySlug.standInPaletteIndex(for: "u-deep-reading", paletteCount: count)))
    }

    @Test func slugsAreCaseSensitive() {
        // DEEP is not deep (ADR 005): an unknown slug, not a built-in.
        #expect(catalog().resolve("DEEP").origin == .standIn)
    }

    @Test func archivedCategoryStillResolvesNameEmojiAndTint() {
        let c = catalog([.fixture(slug: "u-old", name: "Old", emoji: "O", paletteIndex: 3, archivedAt: archivedDate)])
        let r = c.resolve("u-old")
        #expect(r.isArchived)
        #expect(r.name == "Old")
        #expect(r.emoji == "O")
        #expect(r.colorChoice == .palette(3))
        #expect(r.origin == .custom)
    }

    @Test func archivedRowStampsWithArchivedSlug() {
        // A template row left on an archived category keeps stamping its slug; resolution never
        // swaps in another one.
        let c = catalog([.fixture(slug: "u-old", archivedAt: archivedDate)])
        #expect(c.resolve("u-old").slug == "u-old")
    }

    @Test func duplicateDefinitionsFirstWins() {
        let c = catalog([.fixture(slug: "u-x", name: "First"), .fixture(slug: "u-x", name: "Second")])
        #expect(c.resolve("u-x").name == "First")
    }

    // MARK: Colour

    @Test func validCustomHexWinsOverPaletteIndex() {
        let c = catalog([.fixture(slug: "u-a", paletteIndex: 4, customColorHex: "#1a2B3c")])
        #expect(c.resolve("u-a").colorChoice == .custom("#1A2B3C"))
    }

    @Test func invalidCustomHexFallsBackToPaletteIndex() {
        for bad in ["", "#12345", "#1234567", "123456", "#GGGGGG", " #123456", "#123456 ", "#FFF", "#12345678"] {
            let c = catalog([.fixture(slug: "u-a", paletteIndex: 4, customColorHex: bad)])
            #expect(c.resolve("u-a").colorChoice == .palette(4), "hex \(bad.debugDescription)")
        }
    }

    @Test func paletteWrapsDeterministicallyPastCount() {
        let c = catalog([.fixture(slug: "u-a", paletteIndex: 12 + 5), .fixture(slug: "u-b", paletteIndex: -1)])
        #expect(c.resolve("u-a").colorChoice == .palette(5))
        #expect(c.resolve("u-b").colorChoice == .palette(11))
    }

    @Test func choosingPaletteSwatchClearsCustomHex() {
        var d = CategoryDefinitionValue.fixture(slug: "u-a", paletteIndex: 2, customColorHex: "#112233")
        d.choosePalette(6)
        #expect(d.paletteIndex == 6)
        #expect(d.customColorHex == nil)
    }

    @Test func choosingOtherKeepsPaletteIndexAndCanonicalisesHex() {
        var d = CategoryDefinitionValue.fixture(slug: "u-a", paletteIndex: 2)
        let accepted = d.chooseCustom(hex: "#abcdef")
        #expect(accepted)
        #expect(d.customColorHex == "#ABCDEF")
        #expect(d.paletteIndex == 2)
        let rejected = d.chooseCustom(hex: "nope")
        #expect(!rejected)
        #expect(d.customColorHex == "#ABCDEF")   // a rejected pick changes nothing
    }

    @Test func standInNeverResolvesToCustomColor() {
        for slug in ["u-a", "u-b", "mystery", "u-\u{0E01}"] {
            if case .custom = catalog().resolve(slug).colorChoice { Issue.record("custom for \(slug)") }
        }
    }

    @Test func addAsCategoryKeepsStandInPaletteIndex() {
        let c = catalog()
        let before = c.resolve("u-reading")
        let adopted = c.definitionAdopting(standIn: "u-reading", sortIndex: 50)
        #expect(adopted.slug == "u-reading")
        #expect(adopted.customColorHex == nil)
        #expect(adopted.sortIndex == 50)
        #expect(adopted.name == "reading")

        let after = catalog([adopted]).resolve("u-reading")
        #expect(after.colorChoice == before.colorChoice)
        #expect(after.origin == .custom)
    }

    // MARK: Pickers

    @Test func archivedHiddenFromNewChoices() {
        let c = catalog([.fixture(slug: "u-old", archivedAt: archivedDate),
                         .fixture(slug: "admin", name: "Admin", archivedAt: archivedDate),
                         .fixture(slug: "u-new", name: "New", sortIndex: 10)])
        let slugs = c.choices(current: nil).compactMap(\.slug)
        #expect(!slugs.contains("u-old"))
        #expect(!slugs.contains("admin"))
        #expect(slugs.contains("u-new"))
        #expect(slugs.contains("deep"))
    }

    @Test func pickerIncludesCurrentArchivedOrUnknown() {
        let c = catalog([.fixture(slug: "u-old", name: "Old", archivedAt: archivedDate)])
        #expect(c.choices(current: "u-old").compactMap(\.slug).contains("u-old"))
        let unknown = c.choices(current: "u-lost")
        #expect(unknown.last?.slug == "u-lost")
        #expect(unknown.last?.origin == .standIn)
        // An active current is not duplicated.
        #expect(c.choices(current: "rest").compactMap(\.slug).filter { $0 == "rest" }.count == 1)
    }

    @Test func pickerShowsDeepForNilCurrentWhenDeepIsArchived() {
        let c = catalog([.fixture(slug: "deep", name: "Deep work", archivedAt: archivedDate)])
        #expect(c.choices(current: nil).compactMap(\.slug).contains("deep"))
    }

    @Test func choicesAreOrderedBySortIndexWithBuiltInsFirstByDefault() {
        let c = catalog([.fixture(slug: "u-b", sortIndex: 101), .fixture(slug: "u-a", sortIndex: 100)])
        #expect(c.choices(current: nil).compactMap(\.slug)
                == ["deep", "meeting", "admin", "personal", "health", "rest", "u-a", "u-b"])
    }

    @Test func overrideSortIndexReordersABuiltIn() {
        let c = catalog([.fixture(slug: "rest", name: "Rest", sortIndex: -1)])
        #expect(c.choices(current: nil).compactMap(\.slug).first == "rest")
    }

    // MARK: Archiving rule and slug uniqueness

    @Test func atLeastOneCategoryMustStayUnarchived() {
        #expect(catalog().canArchive("deep"))
        let nearlyAll = ["deep", "meeting", "admin", "personal", "health"].map {
            CategoryDefinitionValue.fixture(slug: $0, name: $0, archivedAt: archivedDate)
        }
        let c = catalog(nearlyAll)
        #expect(!c.canArchive("rest"))      // the last active one
        #expect(c.canArchive("deep"))       // already archived: not an issue
    }

    @Test func duplicateSlugInsertIsRejected() {
        // SwiftData's .unique upserts instead of failing, so the catalog has to say no first.
        let c = catalog([.fixture(slug: "u-gym", archivedAt: archivedDate)])
        #expect(c.isSlugTaken("u-gym"))     // archived still counts
        #expect(c.isSlugTaken("deep"))      // built-in with no row still counts
        #expect(!c.isSlugTaken("u-new"))
        #expect(c.takenSlugs.isSuperset(of: CategoryCatalog.builtInSlugs))
    }

    // MARK: Names

    @Test func emptyOrWhitespaceNameIsRejected() {
        for name in ["", "   ", "\n\t", "\u{200B}\u{200C}\u{200D}\u{2060}\u{FEFF}", " \u{200B} "] {
            #expect(catalog().validate(name: name, editing: nil) == .empty, "name \(name.debugDescription)")
        }
    }

    @Test func nameEqualToBuiltInIsRejected() {
        #expect(catalog().validate(name: "Deep work", editing: nil) == .duplicate(ofSlug: "deep"))
        #expect(catalog().validate(name: "  DEEP  WORK ", editing: nil) == .duplicate(ofSlug: "deep"))
        #expect(catalog().validate(name: "Reading", editing: nil) == nil)
    }

    @Test func nameEqualToAnyUnarchivedCustomIsRejected() {
        let c = catalog([.fixture(slug: "u-gym", name: "Gym"),
                         .fixture(slug: "u-old", name: "Old", archivedAt: archivedDate)])
        #expect(c.validate(name: "gym", editing: nil) == .duplicate(ofSlug: "u-gym"))
        // Archived names are free to reuse: the archived one is never in a picker.
        #expect(c.validate(name: "Old", editing: nil) == nil)
    }

    @Test func renamedBuiltInOwnsItsNewNameNotTheOld() {
        let c = catalog([.fixture(slug: "rest", name: "Nap")])
        #expect(c.validate(name: "Rest", editing: nil) == nil)
        #expect(c.validate(name: "nap", editing: nil) == .duplicate(ofSlug: "rest"))
    }

    @Test func editingACategoryMayKeepItsOwnName() {
        let c = catalog([.fixture(slug: "u-gym", name: "Gym")])
        #expect(c.validate(name: "GYM", editing: "u-gym") == nil)
        #expect(c.validate(name: "Meeting", editing: "u-gym") == .duplicate(ofSlug: "meeting"))
    }

    @Test func fullWidthAndThaiDuplicatesAreCaught() {
        let c = catalog([.fixture(slug: "u-x", name: "Gym")])
        #expect(c.validate(name: "\u{FF27}\u{FF59}\u{FF4D}", editing: nil) == .duplicate(ofSlug: "u-x"))
    }

    @Test func emojiIsRequiredAndBlankOrInvisibleIsRefused() {
        #expect(CategoryCatalog.isAcceptableEmoji("\u{1F3CB}"))
        #expect(!CategoryCatalog.isAcceptableEmoji(""))
        #expect(!CategoryCatalog.isAcceptableEmoji("  \u{200B}"))
    }

    @Test func cleanedNameTrimsOnlyEnds() {
        #expect(CategoryCatalog.cleanedName("  Deep  work\n") == "Deep  work")
    }
}
