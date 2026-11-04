#if DEBUG
import Foundation

/// The phone half of ADR 002's experiment 2a, extended for plan task 0.3: does a block's token,
/// including a percent-encoded Thai category slug, survive an iCloud CalDAV round trip and an
/// edit made in Calendar.app or on iCloud.com?
///
/// The simulator already proved the local round trip (ADR 002 addendum, 2026-09-07). Only a real
/// phone with iCloud can answer the rest, so unlike the demo seeding this is not simulator-only.
/// The owner runs it by hand from Settings. It writes exactly one event, into the Blockey calendar.
///
/// This type is the pure half: what was written, and how to judge what came back. EventKit stays
/// in `CalendarService`.
struct TokenProbe: Codable, Equatable, Sendable {
    static let title = "Blockey token test"

    /// Thai with a leading consonant, above and below vowel marks, a tone mark and a space, so a
    /// client that mangles any of percent-encoding, combining marks or spaces shows up. The
    /// escapes spell "งานลึก ทดสอบ" and are written out so the bytes can't be changed by an
    /// editor's normalisation.
    static let slug = "\u{0E07}\u{0E32}\u{0E19}\u{0E25}\u{0E36}\u{0E01} \u{0E17}\u{0E14}\u{0E2A}\u{0E2D}\u{0E1A}"

    var tokenID: UUID
    var sourceTaskID: UUID
    var expectedURL: String
    var eventIdentifier: String?
    var createdAt: Date

    /// The token the probe writes. A fresh source task id rides along so the `t=` parameter is
    /// tested too; it points at no real task.
    var token: BlockToken {
        BlockToken(id: tokenID, categorySlug: Self.slug, sourceTaskID: sourceTaskID)
    }

    enum Found: Equatable, Sendable {
        /// Found by its token id: the token survived well enough to identify the block.
        case byToken
        /// Found only by EventKit identifier: the event is there but its token is gone or broken.
        case byIdentifierOnly
        /// Neither token nor event id matched, but a block with the probe's title is in the
        /// Blockey calendar. That is what a sync that re-created the event looks like.
        case byTitleOnly
        case missing
    }

    /// What `CalendarService` read back for the probe's event.
    struct Observation: Equatable, Sendable {
        var found: Found
        var rawURL: String? = nil
        var eventIdentifier: String? = nil
        var title: String? = nil
        var start: Date? = nil
    }

    /// The parts of the result that decide plan task 0.3.
    struct Verdict: Equatable, Sendable {
        var tokenSurvived: Bool
        var thaiSlugSurvived: Bool
        var taskLinkSurvived: Bool
        var urlByteIdentical: Bool
        var eventIdentifierUnchanged: Bool?

        /// Phase 3 can use Thai slugs as-is only if the slug itself came back intact. A
        /// byte-level url change alone (say, percent-escape case) is fine as long as it parses
        /// back to the same slug, which is why this doesn't look at `urlByteIdentical`.
        var passes: Bool { tokenSurvived && thaiSlugSurvived && taskLinkSurvived }
    }

    func verdict(for observation: Observation) -> Verdict {
        let parsed = observation.rawURL.flatMap(URL.init(string:)).flatMap(BlockToken.init(url:))
        return Verdict(
            tokenSurvived: parsed?.id == tokenID,
            thaiSlugSurvived: parsed?.categorySlug == Self.slug,
            taskLinkSurvived: parsed?.sourceTaskID == sourceTaskID,
            urlByteIdentical: observation.rawURL == expectedURL,
            eventIdentifierUnchanged: observation.eventIdentifier.map { $0 == eventIdentifier })
    }

    /// Plain lines for the Settings screen, written to be screenshotted and read without the
    /// code. English only: the screenshot may end up in a public issue.
    func report(for observation: Observation) -> String {
        func yesNo(_ value: Bool) -> String { value ? "yes" : "NO" }

        switch observation.found {
        case .missing:
            return """
            Not found by token or event id, and no block titled "\(Self.title)" in the Blockey calendar.
            It was deleted, has not synced back yet, or was moved more than 60 days.
            Result: INCONCLUSIVE (block not found)
            """
        case .byTitleOnly:
            return """
            A block titled "\(Self.title)" exists but its token and event id do not match.
            The sync probably re-created the block and dropped the token.
            Result: FAIL (block re-created without its token)
            """
        case .byToken, .byIdentifierOnly:
            break
        }

        let v = verdict(for: observation)
        let decoded = observation.rawURL.flatMap { $0.removingPercentEncoding } ?? "none"
        let parsedSlug = observation.rawURL.flatMap(URL.init(string:)).flatMap(BlockToken.init(url:))?.categorySlug
        var lines = [
            observation.found == .byToken ? "Found by token." : "Found by event id only. The token is gone or broken.",
            "Token id survived: \(yesNo(v.tokenSurvived))",
            "Thai category survived: \(yesNo(v.thaiSlugSurvived))",
            "Task link survived: \(yesNo(v.taskLinkSurvived))",
            "URL byte-identical: \(yesNo(v.urlByteIdentical))",
            "Event id unchanged: \(v.eventIdentifierUnchanged.map(yesNo) ?? "unknown")",
            "Category read back: \(parsedSlug ?? "none")",
            "Decoded URL: \(decoded)",
        ]
        if !v.urlByteIdentical {
            lines.append("Written URL: \(expectedURL)")
            lines.append("Read URL: \(observation.rawURL ?? "none")")
        }
        lines.append(v.passes ? "Result: PASS (Thai slugs survive)" : "Result: FAIL (\(failureReason(v)))")
        return lines.joined(separator: "\n")
    }

    private func failureReason(_ v: Verdict) -> String {
        if !v.tokenSurvived { return "token lost or rewritten" }
        if !v.thaiSlugSurvived { return "Thai category changed" }
        return "task link changed"
    }

    // MARK: - Persistence

    /// The probe is remembered across launches because the experiment spans an iCloud sync and
    /// an edit on another device. UserDefaults survives the weekly reinstall; if it doesn't, the
    /// owner just creates a new probe.
    private static let defaultsKey = "debugTokenProbe"

    static func load(from defaults: UserDefaults = .standard) -> TokenProbe? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(TokenProbe.self, from: data)
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}
#endif
