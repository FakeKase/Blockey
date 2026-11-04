#if DEBUG
import Foundation
import Testing
@testable import Blockey

/// The judging half of the on-phone token experiment (plan task 0.3). The EventKit half only
/// runs by hand on the phone, so these pin what each reading of the result means.
@Suite("Token probe verdicts")
struct TokenProbeTests {
    private func makeProbe() throws -> TokenProbe {
        var probe = TokenProbe(tokenID: UUID(), sourceTaskID: UUID(), expectedURL: "",
                               eventIdentifier: "EV-1", createdAt: .now)
        probe.expectedURL = try #require(probe.token.url?.absoluteString)
        return probe
    }

    @Test("The written URL percent-encodes the Thai slug and parses back to it")
    func writtenURLRoundTrips() throws {
        let probe = try makeProbe()
        #expect(!probe.expectedURL.contains(TokenProbe.slug))
        #expect(probe.expectedURL.contains("%E0%B8"))
        let parsed = try #require(BlockToken(url: URL(string: probe.expectedURL)))
        #expect(parsed.categorySlug == TokenProbe.slug)
        #expect(parsed.sourceTaskID == probe.sourceTaskID)
    }

    @Test("An untouched round trip passes")
    func untouchedPasses() throws {
        let probe = try makeProbe()
        let v = probe.verdict(for: .init(found: .byToken, rawURL: probe.expectedURL, eventIdentifier: "EV-1"))
        #expect(v.passes)
        #expect(v.urlByteIdentical)
        #expect(v.eventIdentifierUnchanged == true)
        #expect(probe.report(for: .init(found: .byToken, rawURL: probe.expectedURL)).hasSuffix("Result: PASS (Thai slugs survive)"))
    }

    @Test("Lower-case percent escapes still pass, but the URL is reported as changed")
    func escapeCaseChangeStillPasses() throws {
        let probe = try makeProbe()
        let lowered = probe.expectedURL.replacingOccurrences(of: "%E0%B8", with: "%e0%b8")
        try #require(lowered != probe.expectedURL)
        let v = probe.verdict(for: .init(found: .byToken, rawURL: lowered))
        #expect(v.passes)
        #expect(!v.urlByteIdentical)
    }

    @Test("A slug that comes back garbled fails")
    func garbledSlugFails() throws {
        let probe = try makeProbe()
        let mangled = try #require(BlockToken(id: probe.tokenID, categorySlug: "????? ?????",
                                              sourceTaskID: probe.sourceTaskID).url?.absoluteString)
        let v = probe.verdict(for: .init(found: .byToken, rawURL: mangled))
        #expect(v.tokenSurvived)
        #expect(!v.thaiSlugSurvived)
        #expect(!v.passes)
    }

    @Test("A stripped URL, found only by event id, fails")
    func strippedURLFails() throws {
        let probe = try makeProbe()
        let observation = TokenProbe.Observation(found: .byIdentifierOnly, rawURL: nil, eventIdentifier: "EV-1")
        #expect(!probe.verdict(for: observation).passes)
        #expect(probe.report(for: observation).hasSuffix("Result: FAIL (token lost or rewritten)"))
    }

    @Test("A URL normalised to https fails")
    func rewrittenSchemeFails() throws {
        let probe = try makeProbe()
        let https = probe.expectedURL.replacingOccurrences(of: "blockey://", with: "https://")
        #expect(!probe.verdict(for: .init(found: .byIdentifierOnly, rawURL: https)).passes)
    }

    @Test("A missing event is inconclusive, not a token failure")
    func missingIsInconclusive() throws {
        let probe = try makeProbe()
        let report = probe.report(for: .init(found: .missing))
        #expect(report.contains("INCONCLUSIVE"))
        #expect(!report.contains("FAIL"))
    }

    @Test("A block re-created under a new id without its token is a named failure")
    func recreatedBlockFails() throws {
        let probe = try makeProbe()
        let report = probe.report(for: .init(found: .byTitleOnly, rawURL: nil, eventIdentifier: "EV-9"))
        #expect(report.hasSuffix("Result: FAIL (block re-created without its token)"))
    }

    @Test("A failing report says why")
    func failureNamesReason() throws {
        let probe = try makeProbe()
        let mangled = try #require(BlockToken(id: probe.tokenID, categorySlug: "abc",
                                              sourceTaskID: probe.sourceTaskID).url?.absoluteString)
        let report = probe.report(for: .init(found: .byToken, rawURL: mangled))
        #expect(report.hasSuffix("Result: FAIL (Thai category changed)"))
    }

    @Test("A lost task link fails even when the Thai slug survives")
    func lostTaskLinkFails() throws {
        let probe = try makeProbe()
        let url = try #require(BlockToken(id: probe.tokenID, categorySlug: TokenProbe.slug).url?.absoluteString)
        let v = probe.verdict(for: .init(found: .byToken, rawURL: url))
        #expect(v.thaiSlugSurvived)
        #expect(!v.taskLinkSurvived)
        #expect(!v.passes)
    }

    @Test("A changed event id is reported, without failing the test")
    func changedIdentifierIsReported() throws {
        let probe = try makeProbe()
        let v = probe.verdict(for: .init(found: .byToken, rawURL: probe.expectedURL, eventIdentifier: "EV-2"))
        #expect(v.eventIdentifierUnchanged == false)
        #expect(v.passes)
    }

    @Test("The probe survives being saved and loaded")
    func persistence() throws {
        let defaults = try #require(UserDefaults(suiteName: "TokenProbeTests-\(UUID().uuidString)"))
        let probe = try makeProbe()
        probe.save(to: defaults)
        #expect(TokenProbe.load(from: defaults) == probe)
        TokenProbe.clear(from: defaults)
        #expect(TokenProbe.load(from: defaults) == nil)
    }
}
#endif
