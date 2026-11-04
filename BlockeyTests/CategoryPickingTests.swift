import Testing
import Foundation
@testable import Blockey

/// UI spec issue #1, sections 1 and 4 (task 3.7): the pure decisions behind the picker, the
/// composer category row and "Add as category". Plain values only; no SwiftData, no views.
@Suite("Category picking")
struct CategoryPickingTests {

    private func def(_ slug: String, _ name: String, sort: Int, archived: Bool = false) -> CategoryDefinitionValue {
        CategoryDefinitionValue(slug: slug, name: name, emoji: "\u{1F4DA}", symbolName: "star.fill",
                                paletteIndex: 7, customColorHex: nil, sortIndex: sort,
                                archivedAt: archived ? TestDates.today() : nil)
    }
    private func catalog(_ defs: [CategoryDefinitionValue] = []) -> CategoryCatalog {
        CategoryCatalog(definitions: defs, paletteCount: 12)
    }

    // MARK: Layout

    @Test func noCurrentSectionForAnActiveCategory() {
        let layout = CategoryChoiceLayout(catalog: catalog(), current: "meeting")
        #expect(layout.current == nil)
        #expect(layout.rows.map(\.slug) == ["deep", "meeting", "admin", "personal", "health", "rest"])
        #expect(layout.selectedSlug == "meeting")
    }

    @Test func nilCurrentChecksTheFallbackAndHasNoCurrentSection() {
        let layout = CategoryChoiceLayout(catalog: catalog(), current: nil)
        #expect(layout.current == nil)
        #expect(layout.selectedSlug == "deep")
    }

    @Test func archivedCurrentMovesToTheCurrentSectionAndOutOfTheList() {
        let c = catalog([def("u-errands", "Errands", sort: 6, archived: true)])
        let layout = CategoryChoiceLayout(catalog: c, current: "u-errands")
        #expect(layout.current?.slug == "u-errands")
        #expect(layout.current?.isArchived == true)
        #expect(!layout.rows.contains { $0.slug == "u-errands" })
        #expect(layout.rows.count == 6)
        #expect(layout.selectedSlug == "u-errands")
    }

    @Test func unknownCurrentIsAStandInInTheCurrentSection() {
        let layout = CategoryChoiceLayout(catalog: catalog(), current: "u-errands")
        #expect(layout.current?.origin == .standIn)
        #expect(layout.rows.count == 6)
    }

    @Test func anArchivedCategoryThatIsNotCurrentIsNeverOffered() {
        let c = catalog([def("u-errands", "Errands", sort: 6, archived: true)])
        let layout = CategoryChoiceLayout(catalog: c, current: "meeting")
        #expect(!layout.chipOrder.contains { $0.slug == "u-errands" })
    }

    @Test func customsAreInterleavedBySortIndexNotGrouped() {
        let c = catalog([def("u-errands", "Errands", sort: 1)])
        let slugs = CategoryChoiceLayout(catalog: c, current: nil).rows.map(\.slug)
        // deep (0), then meeting and errands tie at 1 and the built-in wins the tie.
        #expect(Array(slugs.prefix(3)) == ["deep", "meeting", "u-errands"])
        #expect(slugs.count == 7)
    }

    @Test func chipOrderPutsTheOffListValueLast() {
        let layout = CategoryChoiceLayout(catalog: catalog(), current: "u-errands")
        #expect(layout.chipOrder.last?.slug == "u-errands")
        #expect(layout.chipOrder.count == 7)
    }

    @Test func oneCategoryLeftStillLaysOut() {
        let archivedAll = CategoryCatalog.builtIns.dropLast().enumerated().map {
            def($0.element.slug, $0.element.name, sort: $0.offset, archived: true)
        }
        let layout = CategoryChoiceLayout(catalog: catalog(archivedAll), current: "rest")
        #expect(layout.rows.map(\.slug) == ["rest"])
        #expect(layout.current == nil)
    }

    @Test func fifteenCategoriesAllAppear() {
        let extra = (0..<9).map { def("u-c\($0)", "C\($0)", sort: 10 + $0) }
        let layout = CategoryChoiceLayout(catalog: catalog(extra), current: nil)
        #expect(layout.rows.count == 15)
    }

    // MARK: Copy

    @Test func footerAndSubtitleByStatus() {
        let c = catalog([def("u-errands", "Errands", sort: 6, archived: true)])
        let active = c.resolve("meeting"), archived = c.resolve("u-errands"), standIn = c.resolve("u-lost")
        #expect(CategoryPickerCopy.footer(for: active) == nil)
        #expect(CategoryPickerCopy.subtitle(for: active) == nil)
        #expect(CategoryPickerCopy.footer(for: archived)
                == "\u{201C}Errands\u{201D} is archived. It still shows here, but it won\u{2019}t be offered for new work.")
        #expect(CategoryPickerCopy.subtitle(for: archived) == "Archived")
        #expect(CategoryPickerCopy.footer(for: standIn)
                == "\u{201C}lost\u{201D} isn\u{2019}t saved as a category on this phone.")
        #expect(CategoryPickerCopy.subtitle(for: standIn) == "Not saved as a category")
    }

    @Test func spokenLabels() {
        let c = catalog([def("u-errands", "Errands", sort: 6, archived: true)])
        #expect(CategoryPickerCopy.rowAccessibilityLabel(for: c.resolve("deep")) == "Category, Deep work")
        #expect(CategoryPickerCopy.rowAccessibilityLabel(for: c.resolve("u-errands")) == "Category, Errands, archived")
        #expect(CategoryPickerCopy.rowAccessibilityLabel(for: c.resolve("u-lost"))
                == "Category, lost, not saved as a category")
        #expect(CategoryPickerCopy.listAccessibilityLabel(for: c.resolve("u-errands")) == "Errands, archived")
        #expect(CategoryPickerCopy.listAccessibilityLabel(for: c.resolve("rest")) == "Rest")
    }

    @Test func namesAreNeverTransformed_thaiWithToneMarksIsVerbatim() {
        let thai = "ก\u{0E49}\u{0E32}\u{0E27}\u{0E2B}\u{0E19}\u{0E49}\u{0E32}"
        let c = catalog([def("u-thai", thai, sort: 6, archived: true)])
        #expect(CategoryPickerCopy.footer(for: c.resolve("u-thai"))?.contains(thai) == true)
        #expect(CategoryPickerCopy.listAccessibilityLabel(for: c.resolve("u-thai")).hasPrefix(thai))
    }

    @Test func adoptedAndFailureCopy() {
        #expect(CategoryPickerCopy.adopted(name: "Errands")
                == "Added \u{201C}Errands\u{201D}. Change its emoji and colour in Settings.")
        #expect(CategoryPickerCopy.adoptFailure
                == "Couldn\u{2019}t add this category. Nothing was changed. Try again.")
    }

    // MARK: Adoption

    @Test func adoptingAStandInIsOneTapWithItsOwnColourAndTheTagGlyph() throws {
        let c = catalog()
        guard case .add(let value) = c.planAdoption(of: "u-errands") else {
            Issue.record("expected .add"); return
        }
        let stand = c.resolve("u-errands")
        #expect(value.slug == "u-errands")
        #expect(value.name == "errands")
        #expect(value.emoji == CategoryCatalog.standInEmoji)
        #expect(value.symbolName == CategoryCatalog.standInSymbolName)
        #expect(value.customColorHex == nil)
        #expect(value.sortIndex == 6)
        // Nothing on screen changes colour: the adopted definition resolves to the stand-in's record.
        let after = catalog([value]).resolve("u-errands")
        #expect(after.colors == stand.colors)
        #expect(after.origin == .custom)
    }

    @Test func adoptionSortsLastAmongUnarchived() {
        let c = catalog([def("u-a", "A", sort: 9), def("u-old", "Old", sort: 40, archived: true)])
        guard case .add(let value) = c.planAdoption(of: "u-lost") else { Issue.record("expected .add"); return }
        #expect(value.sortIndex == 10)
    }

    @Test func aCollidingRecoveredNameNeedsTheEditor() {
        // Slug "u-admin" recovers the name "admin", which TitleKey treats as the built-in "Admin".
        guard case .needsRename(let value) = catalog().planAdoption(of: "u-admin") else {
            Issue.record("expected .needsRename"); return
        }
        #expect(value.slug == "u-admin")
    }

    @Test func aCollisionWithAnArchivedNameIsNotACollision() {
        let c = catalog([def("u-old", "errands", sort: 6, archived: true)])
        guard case .add = c.planAdoption(of: "u-errands") else { Issue.record("expected .add"); return }
    }

    @Test func nothingToAdoptForKnownSlugs() {
        let c = catalog([def("u-errands", "Errands", sort: 6)])
        #expect(c.planAdoption(of: "deep") == .notAStandIn)
        #expect(c.planAdoption(of: "u-errands") == .notAStandIn)
        #expect(c.planAdoption(of: nil) == .notAStandIn)
    }

    @Test func nextSortIndexDefaultsToTheBuiltInCount() {
        #expect(catalog().nextSortIndex == 6)
    }

    // MARK: Composer row

    @Test func composerCollapsesPastEightOrAtAccessibilitySizes() {
        #expect(!ComposerCategoryRow.isCollapsed(unarchivedCount: 6, isAccessibilitySize: false))
        #expect(!ComposerCategoryRow.isCollapsed(unarchivedCount: 8, isAccessibilitySize: false))
        #expect(ComposerCategoryRow.isCollapsed(unarchivedCount: 9, isAccessibilitySize: false))
        #expect(ComposerCategoryRow.isCollapsed(unarchivedCount: 6, isAccessibilitySize: true))
    }

    @Test func draftMovesOffAnArchivedFallbackToTheFirstOfferedCategory() {
        var draft = ComposerDraft()
        draft.moveOffArchivedDefault(in: catalog([def("deep", "Deep work", sort: 0, archived: true)]))
        #expect(draft.category == "meeting")
    }

    @Test func draftOnAnOfferedCategoryIsLeftAlone() {
        var draft = ComposerDraft()
        draft.moveOffArchivedDefault(in: catalog())
        #expect(draft.category == "deep")
    }

    @Test func draftStaysPutWhenEveryCategoryIsArchived() {
        var draft = ComposerDraft()
        let all = CategoryCatalog.builtIns.enumerated().map { def($1.slug, $1.name, sort: $0, archived: true) }
        draft.moveOffArchivedDefault(in: catalog(all))
        #expect(draft.category == "deep")
    }

    @Test func draftKeepsAnUnknownSlugItWasGiven() {
        var draft = ComposerDraft()
        draft.category = "u-lost"
        draft.moveOffArchivedDefault(in: catalog())
        #expect(draft.category == "u-lost")
    }

    // MARK: Block sheet

    @Test func untouchedMeansNil() {
        #expect(CategorySelection.slugToSave(initial: nil, current: nil) == nil)
        #expect(CategorySelection.slugToSave(initial: "meeting", current: "meeting") == nil)
        #expect(CategorySelection.slugToSave(initial: "u-lost", current: "u-lost") == nil)
    }

    @Test func aBlockWithNoSlugOpenedAndFallbackPickedStaysUntouched() {
        // Opening a block with no c= and tapping "Deep work" must not write c=deep (spec 0.3).
        #expect(CategorySelection.slugToSave(initial: nil, current: "deep") == nil)
        #expect(CategorySelection.slugToSave(initial: "  ", current: nil) == nil)
    }

    @Test func aRealChangeSavesTheNewSlug() {
        #expect(CategorySelection.slugToSave(initial: nil, current: "rest") == "rest")
        #expect(CategorySelection.slugToSave(initial: "u-lost", current: "deep") == "deep")
        #expect(CategorySelection.slugToSave(initial: "deep", current: "u-lost") == "u-lost")
    }
}
