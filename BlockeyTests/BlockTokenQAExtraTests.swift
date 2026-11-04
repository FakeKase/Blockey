import Testing
import Foundation
@testable import Blockey

// Gaps found in review of the slug change: hostile query items, token equality, and the
// "pick, then pick back" path at the token level.

private let qaID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

@Suite("BlockToken QA extras")
struct BlockTokenQAExtraTests {

    @Test("Hostile unknown query items still regenerate a url that carries the same id")
    func hostileUnknownItemsKeepTheId() throws {
        let names = ["a&b", "=", "#", "%", "ไทย", " ", "x y"]
        let values: [String?] = [nil, "", "a&b=c", "#", "%ZZ", "🙂", String(repeating: "ก", count: 5000)]
        for name in names {
            for value in values {
                var components = URLComponents()
                components.scheme = "blockey"
                components.host = "block"
                components.path = "/\(qaID.uuidString)"
                components.queryItems = [URLQueryItem(name: name, value: value)]
                let url = try #require(components.url)
                let token = try #require(BlockToken(url: url))
                let out = try #require(BlockToken(url: token.url))
                #expect(out.id == qaID)
                #expect(out.unknownQueryItems == token.unknownQueryItems)
            }
        }
    }

    @Test("A nil-valued unknown item keeps having no value")
    func nilValuedItemStaysNil() throws {
        let url = try #require(URL(string: "blockey://block/\(qaID.uuidString)?flag&c=rest"))
        let parsed = try #require(BlockToken(url: url))
        let out = try #require(BlockToken(url: parsed.url))
        #expect(out.unknownQueryItems == [URLQueryItem(name: "flag", value: nil)])
    }

    @Test("Tokens that differ only in unknown items are not equal")
    func unknownItemsParticipateInEquality() throws {
        let ua = try #require(URL(string: "blockey://block/\(qaID.uuidString)?c=rest&x=1"))
        let ub = try #require(URL(string: "blockey://block/\(qaID.uuidString)?c=rest&x=2"))
        let a = try #require(BlockToken(url: ua))
        let b = try #require(BlockToken(url: ub))
        #expect(a != b)
    }

    @Test("Picking a category and then the original one leaves a known slug unchanged")
    func pickAndPickBackKeepsKnownSlug() throws {
        let u = try #require(URL(string: "blockey://block/\(qaID.uuidString)?c=rest&x=1"))
        var token = try #require(BlockToken(url: u))
        let before = token
        token = token.replacingCategorySlug("admin").replacingCategorySlug("rest")
        #expect(token == before)
    }

    @Test("A tokenless block given a category gets a fresh token carrying only that category")
    func tokenlessBlockGainsCategoryOnly() {
        var token = BlockToken()
        token = token.replacingCategorySlug("admin")
        #expect(token.categorySlug == "admin")
        #expect(token.unknownQueryItems.isEmpty)
        #expect(token.sourceTaskID == nil)
    }
}
