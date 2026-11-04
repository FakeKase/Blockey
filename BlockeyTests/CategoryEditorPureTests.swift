import Testing
import Foundation
import UIKit
@testable import Blockey

/// Tasks 3.8 and 3.8b: the pure pieces of UI spec section 9 (lists, ordering, usage copy,
/// default swatch, emoji suggestions, concern copy, name cap) and the editor draft.
@Suite("Category editor, pure layer")
struct CategoryEditorPureTests {

    private func catalog(_ defs: [CategoryDefinitionValue] = []) -> CategoryCatalog {
        CategoryCatalog(definitions: defs)
    }

    // MARK: archived() and activeInOrder()

    @Test func activeInOrderFollowsSortIndexAndSkipsArchived() {
        let c = catalog([.fixture(slug: "u-a", name: "Alpha", sortIndex: -1),
                         .fixture(slug: "u-b", name: "Beta", sortIndex: 1, archivedAt: TestDates.today())])
        let slugs = c.activeInOrder().compactMap(\.slug)
        #expect(slugs.first == "u-a")
        #expect(!slugs.contains("u-b"))
        #expect(slugs.count == CategoryCatalog.builtIns.count + 1)
    }

    @Test func archivedListsOnlyArchivedIncludingABuiltIn() {
        let when = TestDates.today()
        var admin = CategoryCatalog.builtInDefault(slug: "admin")
        admin?.archivedAt = when
        let c = catalog([.fixture(slug: "u-old", name: "Old", sortIndex: 50, archivedAt: when)] + (admin.map { [$0] } ?? []))
        #expect(Set(c.archived().compactMap(\.slug)) == ["admin", "u-old"])
        #expect(c.archived().allSatisfy { $0.isArchived })
        #expect(!c.activeInOrder().contains { $0.slug == "admin" })
    }

    @Test func archivedIsEmptyByDefault() { #expect(catalog().archived().isEmpty) }

    @Test func choicesStillAppendsTheCurrentOffListValue() {
        let c = catalog([.fixture(slug: "u-old", name: "Old", archivedAt: TestDates.today())])
        #expect(c.choices(current: "u-old").last?.slug == "u-old")
        #expect(c.choices(current: nil).count == CategoryCatalog.builtIns.count)
    }

    // MARK: default for new work (archived-fallback fix)

    @Test func newWorkStartsOnDeepWhileItIsOffered() {
        #expect(catalog().defaultSlugForNewWork == "deep")
    }

    @Test func newWorkSkipsAnArchivedDeepForTheFirstActiveCategory() {
        var deep = CategoryCatalog.builtInDefault(slug: "deep")
        deep?.archivedAt = TestDates.today()
        let c = catalog(deep.map { [$0] } ?? [])
        #expect(c.defaultSlugForNewWork == "meeting")
    }

    // MARK: reorder

    @Test func movedMatchesOnMoveSemantics() {
        let a = ["a", "b", "c", "d"]
        #expect(CategoryOrdering.moved(a, fromOffsets: [0], toOffset: 3) == ["b", "c", "a", "d"])
        #expect(CategoryOrdering.moved(a, fromOffsets: [3], toOffset: 0) == ["d", "a", "b", "c"])
        #expect(CategoryOrdering.moved(a, fromOffsets: [1], toOffset: 4) == ["a", "c", "d", "b"])
        #expect(CategoryOrdering.moved(a, fromOffsets: [0, 1], toOffset: 4) == ["c", "d", "a", "b"])
        #expect(CategoryOrdering.moved(a, fromOffsets: [9], toOffset: 0) == a)
    }

    @Test func moveUpAndDownAreAbsentAtTheEnds() {
        let a = ["a", "b", "c"]
        #expect(CategoryOrdering.moved(a, slug: "a", by: -1) == nil)
        #expect(CategoryOrdering.moved(a, slug: "c", by: 1) == nil)
        #expect(CategoryOrdering.moved(a, slug: "b", by: -1) == ["b", "a", "c"])
        #expect(CategoryOrdering.moved(a, slug: "b", by: 1) == ["a", "c", "b"])
        #expect(CategoryOrdering.moved(a, slug: "zz", by: 1) == nil)
    }

    @Test func aMoveRewritesEveryUnarchivedSortIndexAndCreatesRowsForMovedBuiltIns() {
        let c = catalog([.fixture(slug: "u-a", name: "Alpha", sortIndex: 6)])
        var order = c.activeInOrder().compactMap(\.slug)
        order = CategoryOrdering.moved(order, slug: "meeting", by: 1) ?? order   // meeting <-> admin
        let plan = CategoryOrdering.plan(newOrder: order, catalog: c)
        #expect(plan.updates.isEmpty)                    // custom Alpha stayed at 6
        #expect(Set(plan.creations.map(\.slug)) == ["meeting", "admin"])
        #expect(plan.creations.first { $0.slug == "admin" }?.sortIndex == 1)
        #expect(plan.creations.first { $0.slug == "meeting" }?.sortIndex == 2)
        // Rows copy the built-in's defaults.
        #expect(plan.creations.first { $0.slug == "admin" }?.name == "Admin")
    }

    @Test func aMoveUpdatesExistingRowsInPlace() {
        let c = catalog([.fixture(slug: "u-a", name: "Alpha", sortIndex: 6)])
        var order = c.activeInOrder().compactMap(\.slug)
        order = CategoryOrdering.moved(order, slug: "u-a", by: -1) ?? order
        let plan = CategoryOrdering.plan(newOrder: order, catalog: c)
        #expect(plan.updates == ["u-a": 5])
        #expect(plan.creations.map(\.slug) == ["rest"])
        #expect(plan.creations.first?.sortIndex == 6)
    }

    @Test func noMoveIsAnEmptyPlan() {
        let c = catalog()
        #expect(CategoryOrdering.plan(newOrder: c.activeInOrder().compactMap(\.slug), catalog: c).isEmpty)
    }

    @Test func archivedRowsAreNotInThePlanSoTheyKeepTheirIndex() {
        let c = catalog([.fixture(slug: "u-old", name: "Old", sortIndex: 3, archivedAt: TestDates.today())])
        let plan = CategoryOrdering.plan(newOrder: c.activeInOrder().compactMap(\.slug).reversed(), catalog: c)
        #expect(plan.updates["u-old"] == nil)
        #expect(!plan.creations.contains { $0.slug == "u-old" })
    }

    @Test func announcementWords() {
        #expect(CategoryOrdering.announcement(name: "Errands", position: 3, total: 8) == "Moved Errands to position 3 of 8")
    }

    // MARK: usage copy

    @Test func usageSentenceForEveryCountShape() {
        #expect(CategoryUsage.sentence(tasks: 0, rows: 0) == nil)
        #expect(CategoryUsage.sentence(tasks: 3, rows: 2) == "3 inbox tasks and 2 template rows use this category.")
        #expect(CategoryUsage.sentence(tasks: 3, rows: 0) == "3 inbox tasks use this category.")
        #expect(CategoryUsage.sentence(tasks: 1, rows: 0) == "1 inbox task uses this category.")
        #expect(CategoryUsage.sentence(tasks: 0, rows: 2) == "2 template rows use this category.")
        #expect(CategoryUsage.sentence(tasks: 0, rows: 1) == "1 template row uses this category.")
        #expect(CategoryUsage.sentence(tasks: 1, rows: 1) == "1 inbox task and 1 template row use this category.")
        #expect(CategoryUsage.sentence(tasks: 1, rows: 4) == "1 inbox task and 4 template rows use this category.")
    }

    @Test func moveButtonTitleIsSingularAgnosticAsSpecified() {
        #expect(CategoryUsage.moveButtonTitle(count: 5) == "Move 5 and archive")
        #expect(CategoryUsage.moveButtonTitle(count: 1) == "Move 1 and archive")
    }

    @Test func archiveFlowSkipsTheDialogOnlyWhenNothingUsesIt() {
        #expect(ArchiveFlow.decide(tasks: 0, rows: 0) == .archiveNow)
        #expect(ArchiveFlow.decide(tasks: 0, rows: 1) == .askWhereToMove(tasks: 0, rows: 1))
    }

    @Test func archiveCopyUsesCurlyQuotes() {
        #expect(CategoryUsage.archiveTitle(name: "Errands") == "Archive \u{201C}Errands\u{201D}?")
        #expect(CategoryUsage.archiveFailure(name: "Errands").hasPrefix("Couldn\u{2019}t archive \u{201C}Errands\u{201D}."))
    }

    // MARK: default swatch (spec 3.4)

    @Test func aNewCategoryStartsOnTheFirstSwatchNobodyUses() {
        // Built-ins use palette 0...5. Picker order starts 6 (Red), which is free.
        #expect(catalog().defaultPaletteIndexForNewCategory == 6)
    }

    @Test func aCustomColourUsesNoSwatch() {
        let c = catalog([.fixture(slug: "u-a", name: "A", paletteIndex: 6, customColorHex: "#FF8800", sortIndex: 6)])
        #expect(c.defaultPaletteIndexForNewCategory == 6)
    }

    @Test func anArchivedCategoryFreesItsSwatch() {
        let c = catalog([.fixture(slug: "u-a", name: "A", paletteIndex: 6, sortIndex: 6, archivedAt: TestDates.today())])
        #expect(c.defaultPaletteIndexForNewCategory == 6)
        let used = catalog([.fixture(slug: "u-a", name: "A", paletteIndex: 6, sortIndex: 6)])
        #expect(used.defaultPaletteIndexForNewCategory == 7)   // Gold, next in picker order
    }

    @Test func aFullPaletteAdvancesByCount() {
        let all = Set(0..<CategoryPalette.count)
        #expect(CategoryPalette.defaultIndex(avoiding: all, unarchivedCount: 0) == CategoryPalette.pickerOrder[0])
        #expect(CategoryPalette.defaultIndex(avoiding: all, unarchivedCount: 14) == CategoryPalette.pickerOrder[2])
        #expect(CategoryPalette.defaultIndex(avoiding: [], unarchivedCount: 3) == CategoryPalette.pickerOrder[0])
    }

    // MARK: emoji suggestions and symbol fallback

    @Test func thirtySuggestionsAllDistinctWithSymbolsThatExist() {
        #expect(EmojiSuggestions.all.count == 30)
        #expect(Set(EmojiSuggestions.all.map(\.emoji)).count == 30)
        for s in EmojiSuggestions.all {
            #expect(UIImage(systemName: s.symbolName) != nil, "missing symbol \(s.symbolName)")
        }
        #expect(UIImage(systemName: EmojiSuggestions.fallbackSymbol) != nil)
    }

    @Test func noSuggestionIsABuiltInEmoji() {
        let builtIn = Set(CategoryCatalog.builtIns.map { EmojiSuggestions.comparisonKey($0.emoji) })
        for s in EmojiSuggestions.all { #expect(!builtIn.contains(EmojiSuggestions.comparisonKey(s.emoji))) }
    }

    @Test func symbolRuleOrder() {
        #expect(EmojiSuggestions.symbol(for: "\u{1F4DA}") == "books.vertical.fill")
        // Rule 1 beats a stored pair.
        #expect(EmojiSuggestions.symbol(for: "\u{1F4DA}", keeping: [("\u{1F4DA}", "x")]) == "books.vertical.fill")
        // Rule 2: unchanged from the stored emoji.
        #expect(EmojiSuggestions.symbol(for: "\u{1F9E0}", keeping: [("\u{1F9E0}", "brain.head.profile")]) == "brain.head.profile")
        // Rule 3: anything else, and never `tag`.
        #expect(EmojiSuggestions.symbol(for: "\u{1F9E0}") == "star.fill")
        #expect(EmojiSuggestions.fallbackSymbol != CategoryCatalog.standInSymbolName)
    }

    @Test func aMissingVariationSelectorStillFindsTheSuggestion() {
        #expect(EmojiSuggestions.symbol(for: "\u{2708}") == "airplane")
        #expect(EmojiSuggestions.label(for: "\u{2708}") == "Flights")
    }

    @Test func freeEntryKeepsTheLastCharacterOnly() {
        #expect(EmojiEntry.lastCharacter(of: "\u{1F600}\u{1F3A8}") == "\u{1F3A8}")
        #expect(EmojiEntry.lastCharacter(of: "") == "")
        // A family emoji is one Character, not several.
        #expect(EmojiEntry.lastCharacter(of: "a\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}") == "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}")
    }

    // MARK: name cap

    @Test func nameCapIsByCharacterNotByScalar() {
        let thai = String(repeating: "\u{0E01}\u{0E49}", count: 30)   // 30 clusters, 60 scalars
        let clamped = CategoryNameField.clamped(thai)
        #expect(clamped.count == 24)
        #expect(clamped.unicodeScalars.count == 48)
        #expect(clamped.last == "\u{0E01}\u{0E49}")                  // no tone mark cut off
        #expect(CategoryNameField.clamped("short") == "short")
        #expect(CategoryNameField.clamped(String(repeating: "a", count: 24)).count == 24)
        #expect(CategoryNameField.isAtCap(String(repeating: "a", count: 24)))
        #expect(!CategoryNameField.isAtCap(String(repeating: "a", count: 23)))
    }

    // MARK: concern copy

    private func concern(_ kind: ColorConcern.Kind, dark: Bool) -> ColorConcern { ColorConcern(kind: kind, isDark: dark) }

    @Test func concernSentencesFoldBothModes() {
        let name: (String) -> String = { _ in "Admin" }
        #expect(ColorConcernCopy.line(for: [], isGrey: false, nameFor: name) == nil)
        #expect(ColorConcernCopy.line(for: [concern(.lowContrast, dark: false)], isGrey: false, nameFor: name)
                == "Title may be hard to read in light mode")
        #expect(ColorConcernCopy.line(for: [concern(.lowContrast, dark: true)], isGrey: false, nameFor: name)
                == "Title may be hard to read in dark mode")
        #expect(ColorConcernCopy.line(for: [concern(.lowContrast, dark: false), concern(.lowContrast, dark: true)],
                                      isGrey: false, nameFor: name) == "Title may be hard to read in light and dark mode")
        #expect(ColorConcernCopy.line(for: [concern(.looksLikeMeeting, dark: true)], isGrey: false, nameFor: name)
                == "Looks like a meeting in dark mode")
        #expect(ColorConcernCopy.line(for: [concern(.looksLikeMeeting, dark: false), concern(.looksLikeMeeting, dark: true)],
                                      isGrey: false, nameFor: name) == "Looks like a meeting in light and dark mode")
        #expect(ColorConcernCopy.line(for: [concern(.closeTo(slug: "admin"), dark: false)], isGrey: false, nameFor: name)
                == "Close to Admin in light mode")
    }

    @Test func onlyTheWorstConcernShowsAndCloseToFoldsPerSlug() {
        let name: (String) -> String = { $0 == "admin" ? "Admin" : "Rest" }
        // Low contrast outranks everything after it.
        let mixed = [concern(.lowContrast, dark: true), concern(.looksLikeMeeting, dark: false)]
        #expect(ColorConcernCopy.line(for: mixed, isGrey: false, nameFor: name) == "Title may be hard to read in dark mode")
        // Two different neighbours: only the first is named, and its modes are its own.
        let close = [concern(.closeTo(slug: "admin"), dark: false), concern(.closeTo(slug: "rest"), dark: true),
                     concern(.closeTo(slug: "admin"), dark: true)]
        #expect(ColorConcernCopy.line(for: close, isGrey: false, nameFor: name) == "Close to Admin in light and dark mode")
    }

    @Test func aGreyPickReplacesTheMeetingLineButNotLowContrast() {
        let name: (String) -> String = { $0 }
        #expect(ColorConcernCopy.line(for: [concern(.looksLikeMeeting, dark: false)], isGrey: true, nameFor: name)
                == "Too grey to tell apart from a meeting")
        #expect(ColorConcernCopy.line(for: [concern(.lowContrast, dark: false), concern(.looksLikeMeeting, dark: false)],
                                      isGrey: true, nameFor: name) == "Title may be hard to read in light mode")
        #expect(ColorConcernCopy.spoken("Looks like a meeting in dark mode") == "Warning. Looks like a meeting in dark mode")
        #expect(ColorConcernCopy.derivedNote == "Blockey adjusts brightness for light and dark mode. Your pick sets the hue.")
    }

    // MARK: the draft

    @Test func addStartsEmptyOnTheDefaultSwatchAndIsNotDirty() throws {
        let d = try #require(CategoryDraft(mode: .add, catalog: catalog()))
        #expect(d.value.name.isEmpty && d.value.emoji.isEmpty)
        #expect(d.value.paletteIndex == 6)
        #expect(!d.isDirty)
        #expect(!d.canSave(in: catalog()))
    }

    @Test func addNeedsANameAndAnEmojiAndOffersNoReset() throws {
        let c = catalog()
        var d = try #require(CategoryDraft(mode: .add, catalog: c))
        d.setName("Errands")
        #expect(d.isDirty && !d.canSave(in: c))        // no emoji yet
        d.chooseEmoji("\u{1F6D2}")
        #expect(d.canSave(in: c))
        #expect(d.value.symbolName == "cart.fill")
        #expect(!d.canReset)
    }

    @Test func blankAndDuplicateNamesBlockSave() throws {
        let c = catalog()
        var d = try #require(CategoryDraft(mode: .add, catalog: c))
        d.chooseEmoji("\u{1F6D2}")
        d.setName("   ")
        #expect(d.nameProblem(in: c) == .empty && !d.canSave(in: c))
        d.setName("admin")
        #expect(d.nameProblem(in: c) == .duplicate(ofSlug: "admin") && !d.canSave(in: c))
        #expect(CategoryEditorCopy.nameMessage(.duplicate(ofSlug: "admin"), catalog: c)
                == "Another category is already called \u{201C}Admin\u{201D}. Choose a different name.")
        d.setName("Errands")
        #expect(d.canSave(in: c))
    }

    @Test func nameIsCappedAsTyped() throws {
        var d = try #require(CategoryDraft(mode: .add, catalog: catalog()))
        d.setName(String(repeating: "x", count: 40))
        #expect(d.value.name.count == 24)
    }

    @Test func editNeedsAChangeAndLeavingItsOwnNameAloneIsNotADuplicate() throws {
        let c = catalog()
        var d = try #require(CategoryDraft(mode: .edit(slug: "admin"), catalog: c))
        #expect(d.nameProblem(in: c) == nil)
        #expect(!d.isDirty && !d.canSave(in: c))
        d.choosePalette(7)
        #expect(d.isDirty && d.canSave(in: c))
        d.choosePalette(2)                                   // back to where it started
        #expect(!d.isDirty)
    }

    @Test func trailingSpacesAloneAreNotAChange() throws {
        var d = try #require(CategoryDraft(mode: .edit(slug: "admin"), catalog: catalog()))
        d.setName("Admin  ")
        #expect(!d.isDirty)
    }

    @Test func choosingASwatchClearsTheCustomColourAndOtherLeavesTheSwatch() throws {
        var d = try #require(CategoryDraft(mode: .add, catalog: catalog()))
        #expect(d.selectedPaletteIndex == 6)
        let accepted = d.chooseCustom(hex: "#336699")
        #expect(accepted)
        #expect(d.selectedPaletteIndex == nil && d.usesCustomColor && d.value.paletteIndex == 6)
        let rejected = d.chooseCustom(hex: "blue")
        #expect(!rejected)
        #expect(d.value.customColorHex == "#336699")
        d.choosePalette(1)
        #expect(d.selectedPaletteIndex == 1 && !d.usesCustomColor && d.value.customColorHex == nil)
    }

    @Test func resetToDefaultLoadsFactoryValuesAndIsOnlyOfferedWhenDifferent() throws {
        let c = catalog([.fixture(slug: "admin", name: "Paperwork", emoji: "\u{1F4DA}", symbolName: "books.vertical.fill",
                                  paletteIndex: 7, customColorHex: "#112233", sortIndex: 2)])
        var d = try #require(CategoryDraft(mode: .edit(slug: "admin"), catalog: c))
        #expect(d.canReset)
        d.resetToDefault()
        #expect(d.value.name == "Admin" && d.value.emoji == "\u{1F5C2}\u{FE0F}" && d.value.symbolName == "tray.full.fill")
        #expect(d.value.paletteIndex == 2 && d.value.customColorHex == nil)
        #expect(!d.canReset)
        #expect(d.value.sortIndex == 2 && d.value.archivedAt == nil)
        #expect(d.canSave(in: c))                             // differs from where the editor started
        let untouched = try #require(CategoryDraft(mode: .edit(slug: "meeting"), catalog: c))
        #expect(!untouched.canReset)
        let custom = catalog([.fixture(slug: "u-a", name: "A", sortIndex: 6)])
        let customDraft = try #require(CategoryDraft(mode: .edit(slug: "u-a"), catalog: custom))
        #expect(customDraft.canReset == false)
    }

    @Test func aResetBuiltInRegainsItsOwnSymbolWhenItsEmojiComesBack() throws {
        let c = catalog()
        var d = try #require(CategoryDraft(mode: .edit(slug: "rest"), catalog: c))
        d.chooseEmoji("\u{1F634}")
        #expect(d.value.symbolName == "bed.double.fill")
        d.chooseEmoji("\u{2615}")
        #expect(d.value.symbolName == "cup.and.saucer.fill")
    }

    @Test func archivedModeRestoresWithoutAChangeButNotOnADuplicateName() throws {
        let when = TestDates.today()
        let c = catalog([.fixture(slug: "u-old", name: "Admin", emoji: "X", sortIndex: 9, archivedAt: when)])
        let d = try #require(CategoryDraft(mode: .archived(slug: "u-old"), catalog: c))
        #expect(d.nameProblem(in: c) == .duplicate(ofSlug: "admin"))
        #expect(!d.canRestore(in: c) && !d.canSave(in: c))
        let ok = catalog([.fixture(slug: "u-old", name: "Old", emoji: "X", sortIndex: 9, archivedAt: when)])
        let d2 = try #require(CategoryDraft(mode: .archived(slug: "u-old"), catalog: ok))
        #expect(d2.canRestore(in: ok) && !d2.canSave(in: ok))
        #expect(CategoryDraft(mode: .edit(slug: "u-old"), catalog: ok)?.canRestore(in: ok) == false)
    }

    @Test func adoptKeepsTheStandInsSlugColourAndTag() throws {
        let c = catalog()
        let d = try #require(CategoryDraft(mode: .adopt(slug: "u-errands"), catalog: c))
        let stand = c.resolve("u-errands")
        #expect(d.value.slug == "u-errands" && d.value.name == "errands")
        #expect(d.colorChoice == stand.colorChoice)
        #expect(d.value.emoji == CategoryCatalog.standInEmoji && d.value.symbolName == "tag")
        #expect(d.canSave(in: c))                                   // a new row, no change needed
        #expect(!d.isDirty)
        #expect(CategoryDraft(mode: .adopt(slug: "deep"), catalog: c) == nil)
        #expect(CategoryDraft(mode: .edit(slug: "u-errands"), catalog: c) == nil)
    }

    @Test func aCollidingAdoptNameShowsTheDuplicateAtOnce() throws {
        let c = catalog()
        let d = try #require(CategoryDraft(mode: .adopt(slug: "admin-"), catalog: c))
        // "admin-" recovers to "admin", which collides with the built-in Admin.
        #expect(d.nameProblem(in: c) == .duplicate(ofSlug: "admin"))
        #expect(!d.canSave(in: c))
    }

    // MARK: warnings in the draft

    @Test func aSwatchAgainstTheCuratedSetRaisesNothing() throws {
        var d = try #require(CategoryDraft(mode: .add, catalog: catalog()))
        for index in 6...11 {                                       // the six no built-in uses
            d.choosePalette(index)
            #expect(d.warningLine(in: catalog()) == nil, "swatch \(index)")
        }
    }

    @Test func aGreyPickWarnsInTheGreyWords() throws {
        var d = try #require(CategoryDraft(mode: .add, catalog: catalog()))
        d.chooseCustom(hex: "#808080")
        #expect(d.isGreyPick)
        #expect(d.warningLine(in: catalog()) == "Too grey to tell apart from a meeting")
    }

    @Test func aPickCloseToAnotherCategoryNamesItButNotItself() throws {
        let c = catalog()
        // Admin's own swatch derived as a custom colour must be near Admin, never "near itself".
        var add = try #require(CategoryDraft(mode: .add, catalog: c))
        add.choosePalette(2)                                       // Teal, which Admin uses
        let line = try #require(add.warningLine(in: c))
        #expect(line.hasPrefix("Close to Admin in "))
        var edit = try #require(CategoryDraft(mode: .edit(slug: "admin"), catalog: c))
        edit.choosePalette(2)
        #expect(edit.warningLine(in: c) == nil)
    }

    @Test func archivedCategoriesAreNotComparedAgainst() throws {
        var admin = try #require(CategoryCatalog.builtInDefault(slug: "admin"))
        admin.archivedAt = TestDates.today()
        let c = catalog([admin])
        var add = try #require(CategoryDraft(mode: .add, catalog: c))
        add.choosePalette(2)
        #expect(add.warningLine(in: c) == nil)
    }

    @Test func aPickedColourIsClampedToSRGBBeforeItIsStored() {
        // A Display P3 pick can come back outside 0...1; the hex must still be a valid #RRGGBB.
        #expect(SRGB(r: 1.08, g: -0.04, b: 0.5).hex == "#FF0080")
        #expect(CategoryCatalog.canonicalHex(SRGB(r: 1.08, g: -0.04, b: 0.5).hex) != nil)
    }

    // MARK: editor copy

    @Test func editorStrings() {
        #expect(CategoryEditorCopy.emojiFooter(canTypeOwn: true).hasSuffix("switch to the emoji keyboard."))
        #expect(!CategoryEditorCopy.emojiFooter(canTypeOwn: false).contains("keyboard"))
        #expect(CategoryEditorCopy.swatchLabel(name: "Red", position: 1, total: 12) == "Red, colour 1 of 12")
        #expect(CategoryEditorMode.add.title == "New category")
        #expect(CategoryEditorMode.edit(slug: "x").title == "Edit category")
        #expect(CategoryEditorMode.adopt(slug: "x").title == "Add category")
    }
}
