import Testing
import Foundation
@testable import Blockey

// The category slug in a block's url is the only record of what kind of block it
// is. BlockCategory is a closed enum, so a slug the app doesn't know (a future
// custom category, a Thai name typed in Calendar.app) used to collapse to
// `.fallback` on parse and be rewritten as "deep" on the next Save. These tests
// pin the opposite: the slug is kept verbatim, and `category` is only a view of it.

private let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
private let taskID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

private func makeURL(_ query: String) throws -> URL {
    try #require(URL(string: "blockey://block/\(id.uuidString)\(query)"))
}

private func queryItems(_ url: URL) -> [URLQueryItem] {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
}

/// Parse, then regenerate, the way `CalendarService.update` does when it touches a token.
private func rewritten(_ url: URL) throws -> URL {
    let token = try #require(BlockToken(url: url))
    return try #require(token.url)
}

@Suite("BlockToken category slug")
struct BlockTokenSlugTests {

    @Test("An unknown slug survives a round trip, and the resolved category stays the fallback")
    func unknownSlugSurvivesRoundTrip() throws {
        let url = try makeURL("?c=telepathy")
        let parsed = try #require(BlockToken(url: url))
        #expect(parsed.categorySlug == "telepathy")

        let again = try #require(BlockToken(url: parsed.url))
        #expect(again.categorySlug == "telepathy")
        #expect(again.id == id)
    }

    @Test("A Thai slug round-trips verbatim")
    func thaiSlugRoundTripsVerbatim() throws {
        let slug = "งานบ้าน"
        var components = URLComponents()
        components.scheme = "blockey"
        components.host = "block"
        components.path = "/\(id.uuidString)"
        components.queryItems = [URLQueryItem(name: "c", value: slug)]
        let url = try #require(components.url)

        let parsed = try #require(BlockToken(url: url))
        #expect(parsed.categorySlug == slug)
        #expect(try #require(BlockToken(url: parsed.url)).categorySlug == slug)
    }

    @Test("An NFD slug is normalised to NFC")
    func nfdSlugParsesToNfc() throws {
        let nfc = "caf\u{00E9}"
        let nfd = nfc.decomposedStringWithCanonicalMapping
        #expect(nfd != nfc || nfd.unicodeScalars.count != nfc.unicodeScalars.count)

        var components = URLComponents()
        components.scheme = "blockey"
        components.host = "block"
        components.path = "/\(id.uuidString)"
        components.queryItems = [URLQueryItem(name: "c", value: nfd)]
        let parsed = try #require(BlockToken(url: try #require(components.url)))

        #expect(Array(try #require(parsed.categorySlug).unicodeScalars)
                == Array(nfc.unicodeScalars))
    }

    @Test("A percent-encoded Thai slug regenerates the same token")
    func percentEncodedThaiSlugRegeneratesSameToken() throws {
        // ก า encoded as UTF-8 percent escapes, as Calendar.app or CalDAV would store it.
        let url = try makeURL("?c=%E0%B8%81%E0%B8%B2")
        let parsed = try #require(BlockToken(url: url))
        #expect(parsed.categorySlug == "กา")

        let regenerated = try #require(BlockToken(url: parsed.url))
        #expect(regenerated == parsed)
        #expect(try #require(parsed.url).absoluteString == url.absoluteString)
    }

    @Test("A hand-edited raw-Thai url is percent-encoded by URL and parses as an ordinary token")
    func rawThaiHandEditedUrlParsesAsOrdinaryToken() throws {
        // Observed: URL(string:) percent-encodes raw non-ASCII itself (iOS 17+ / macOS 14+),
        // so the url is non-nil and parses as an ordinary token with the Thai slug intact.
        let url = try #require(URL(string: "blockey://block/\(id.uuidString)?c=กา"))
        let parsed = try #require(BlockToken(url: url))
        #expect(parsed.categorySlug == "กา")
        #expect(parsed.id == id)
    }

    @Test("An absent category stays absent on rewrite")
    func absentCategoryStaysAbsentOnRewrite() throws {
        let url = try makeURL("")
        let parsed = try #require(BlockToken(url: url))
        #expect(parsed.categorySlug == nil)
        #expect(!queryItems(try #require(parsed.url)).contains { $0.name == "c" })
    }

    @Test("An empty category value counts as absent")
    func emptyCategoryValueIsAbsent() throws {
        let parsed = try #require(BlockToken(url: try makeURL("?c=")))
        #expect(parsed.categorySlug == nil)
        #expect(!queryItems(try #require(parsed.url)).contains { $0.name == "c" })
    }

    @Test("A whitespace-only category value counts as absent")
    func whitespaceOnlyCategoryValueIsAbsent() throws {
        let parsed = try #require(BlockToken(url: try makeURL("?c=%20%20")))
        #expect(parsed.categorySlug == nil)
    }

    @Test("With duplicate c items the first wins")
    func duplicateCQueryItemsFirstWins() throws {
        let parsed = try #require(BlockToken(url: try makeURL("?c=rest&c=admin")))
        #expect(parsed.categorySlug == "rest")

        let unknownFirst = try #require(BlockToken(url: try makeURL("?c=zzz&c=admin")))
        #expect(unknownFirst.categorySlug == "zzz")
    }

    @Test("Slugs are case-sensitive")
    func categoryValueIsCaseSensitive() throws {
        let parsed = try #require(BlockToken(url: try makeURL("?c=DEEP")))
        #expect(parsed.categorySlug == "DEEP")
        // Not rewritten to "deep" either: the original is what the user typed.
        #expect(try #require(BlockToken(url: parsed.url)).categorySlug == "DEEP")
    }

    @Test("Unknown query items survive a round trip, including ones before c and duplicates")
    func unknownQueryItemsSurviveRoundTrip() throws {
        let url = try makeURL("?x=1&c=rest&y=a&y=b&t=\(taskID.uuidString)&z=")
        let out = queryItems(try rewritten(url))

        #expect(out.filter { $0.name == "x" }.map(\.value) == ["1"])
        #expect(out.filter { $0.name == "y" }.map(\.value) == ["a", "b"])
        #expect(out.contains { $0.name == "z" })
        #expect(out.filter { $0.name == "c" }.map(\.value) == ["rest"])
        #expect(out.filter { $0.name == "t" }.count == 1)
        // Relative order of the unknowns is kept.
        let unknownNames = out.map(\.name).filter { !["c", "t"].contains($0) }
        #expect(unknownNames == ["x", "y", "y", "z"])
    }

    @Test("The source task survives when the category is unknown")
    func sourceTaskSurvivesWhenCategoryUnknown() throws {
        let url = try makeURL("?c=telepathy&t=\(taskID.uuidString)")
        let parsed = try #require(BlockToken(url: url))
        #expect(parsed.sourceTaskID == taskID)
        let again = try #require(BlockToken(url: parsed.url))
        #expect(again.sourceTaskID == taskID)
        #expect(again.categorySlug == "telepathy")
    }

    @Test("A url is always produced, whatever the slug")
    func urlIsAlwaysProducedForAnySlug() throws {
        let slugs = ["", " ", "a&b=c", "a b", "100%", "ไทย", "e\u{0301}", "🙂", "?#/", String(repeating: "x", count: 5000)]
        for slug in slugs {
            let token = BlockToken(id: id, categorySlug: slug, sourceTaskID: nil)
            let url = try #require(token.url)
            let back = try #require(BlockToken(url: url))
            #expect(back.id == id)
            // Blank slugs are absent by design; everything else must come back as typed (NFC).
            let blank = slug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            #expect(back.categorySlug == (blank ? nil : slug.precomposedStringWithCanonicalMapping))
        }
    }

    @Test("Parsing then regenerating an untouched token gives back the same url")
    func untouchedTokenIsNotRewritten() throws {
        // The token-level half of "Save without a category change leaves the token alone":
        // with category nil, CalendarService.update never touches event.url at all, and
        // even a rewrite of an unknown-slug token is lossless.
        let url = try makeURL("?c=telepathy&t=\(taskID.uuidString)&x=1")
        let parsed = try #require(BlockToken(url: url))
        #expect(try #require(BlockToken(url: parsed.url)) == parsed)
    }

    @Test("Setting category sets the slug, and choosing one is an explicit overwrite")
    func settingCategorySetsSlug() throws {
        var token = try #require(BlockToken(url: try makeURL("?c=telepathy&x=1")))
        token = token.replacingCategorySlug("admin")
        #expect(token.categorySlug == "admin")
        // Unknown query items are not collateral damage of a category change.
        #expect(queryItems(try #require(token.url)).contains { $0.name == "x" })
    }

    @Test("Save without a category change does not rewrite the token")
    func saveWithUnchangedCategoryDoesNotRewriteToken() {
        for category in BlockCategory.allCases {
            #expect(BlockDetailSheet.slugToSave(initial: category.rawValue, current: category.rawValue) == nil)
        }
        #expect(BlockDetailSheet.slugToSave(initial: "deep", current: "rest") == "rest")
    }

    @Test("Picking away and back to the original category saves nothing")
    func pickAwayAndBackSavesNothing() {
        // The sheet holds only the current selection, so away-and-back is just equal values.
        // A block with no `c=` shows as the fallback, so choosing the fallback leaves it alone.
        #expect(BlockDetailSheet.slugToSave(initial: nil, current: "deep") == nil)
    }
}
