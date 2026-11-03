import Foundation

/// One remembered use of a title. `date` is nil for template rows.
struct TitleSample: Hashable, Sendable {
    let title: String
    let minutes: Int
    let categorySlug: String?
    let date: Date?
}

/// What a chip shows and what a tap restores.
struct TitleSuggestion: Hashable, Sendable {
    let title: String
    let minutes: Int
    /// Nil when the remembered slug is unknown or archived: the composer keeps its own category.
    let categorySlug: String?
}

/// Ranks previously used titles against what the user has typed. Pure: no EventKit, SwiftUI or
/// SwiftData. See ADR 006.
enum TitleSuggestions {

    static let defaultLimit = 3
    /// 0.5 is the weight of one use `halfLifeDays` ago.
    static let halfLifeDays = 14.0
    static let templateWeight = 0.5

    private enum Match: Int, Comparable {
        case exact, prefix, wordPrefix, substring
        static func < (a: Match, b: Match) -> Bool { a.rawValue < b.rawValue }
    }

    private struct Group {
        var latest: TitleSample
        var latestOrder: Int
        var score: Double
    }

    static func suggest(query: String,
                        history: [TitleSample],
                        templates: [TitleSample],
                        knownSlugs: Set<String>,
                        now: Date,
                        limit: Int = defaultLimit) -> [TitleSuggestion] {
        guard limit > 0 else { return [] }
        let queryScalars = Array(TitleKey.normalize(query).unicodeScalars)
        guard let first = queryScalars.first, !cannotStartMatch(first) else { return [] }

        let excluded = TitleKey.normalize(DefaultTitles.newBlock)

        // History: summed recency weight per key; the latest sample supplies spelling, minutes, slug.
        var groups: [String: Group] = [:]
        for (order, s) in history.enumerated() {
            let key = TitleKey.normalize(s.title)
            if key.isEmpty || key == excluded { continue }
            let weight = s.date.map { recencyWeight(of: $0, now: now) } ?? templateWeight
            if var g = groups[key] {
                g.score += weight
                if isLater(s, order, than: g.latest, g.latestOrder) { g.latest = s; g.latestOrder = order }
                groups[key] = g
            } else {
                groups[key] = Group(latest: s, latestOrder: order, score: weight)
            }
        }

        // Templates only fill keys history does not have, so a stamped template is not counted twice.
        var templateGroups: [String: Group] = [:]
        for (order, s) in templates.enumerated() {
            let key = TitleKey.normalize(s.title)
            if key.isEmpty || key == excluded || groups[key] != nil { continue }
            // Later rows win, as the last spelling typed.
            templateGroups[key] = Group(latest: s, latestOrder: order, score: templateWeight)
        }
        groups.merge(templateGroups) { current, _ in current }

        struct Candidate { let match: Match; let score: Double; let key: String; let latest: TitleSample }
        var candidates: [Candidate] = []
        for (key, g) in groups {
            guard let match = matchQuality(Array(key.unicodeScalars), queryScalars) else { continue }
            candidates.append(Candidate(match: match, score: g.score, key: key, latest: g.latest))
        }

        candidates.sort { a, b in
            if a.match != b.match { return a.match < b.match }
            if a.score != b.score { return a.score > b.score }
            if a.latest.title != b.latest.title { return a.latest.title < b.latest.title }
            return a.key < b.key
        }

        return candidates.prefix(limit).map { c in
            TitleSuggestion(title: c.latest.title.trimmingCharacters(in: .whitespacesAndNewlines),
                            minutes: c.latest.minutes,
                            categorySlug: c.latest.categorySlug.flatMap { knownSlugs.contains($0) ? $0 : nil })
        }
    }

    // MARK: Private

    private static func recencyWeight(of date: Date, now: Date) -> Double {
        let ageDays = max(0, now.timeIntervalSince(date)) / 86_400
        return pow(0.5, ageDays / halfLifeDays)
    }

    /// Later date wins; on equal dates the later array position, so the answer does not depend on
    /// hash order.
    private static func isLater(_ a: TitleSample, _ aOrder: Int, than b: TitleSample, _ bOrder: Int) -> Bool {
        let da = a.date ?? .distantPast, db = b.date ?? .distantPast
        return da != db ? da > db : aOrder > bOrder
    }

    /// A lone combining mark, or a Thai vowel that can only follow a consonant (non-initial Lo:
    /// U+0E30, U+0E32, U+0E33, U+0E45, U+0E4D), would substring-match nearly everything. The
    /// leading vowels U+0E40 to U+0E44 start syllables and stay valid.
    private static func cannotStartMatch(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x0E30, 0x0E32, 0x0E33, 0x0E45, 0x0E4D: return true
        default: return isCombining(s)
        }
    }

    private static func isCombining(_ s: Unicode.Scalar) -> Bool {
        switch s.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return false
        }
    }

    /// Compares Unicode scalars, not grapheme clusters, so a partial Thai cluster matches
    /// (`ก` is not a prefix of `กิน` by `Character`, but is by scalar).
    private static func matchQuality(_ key: [Unicode.Scalar], _ query: [Unicode.Scalar]) -> Match? {
        let n = key.count, m = query.count
        guard m <= n else { return nil }
        // Equal length: the only possible alignment is the whole key.
        if m == n { return key == query ? .exact : nil }

        var best: Match?
        var i = 0
        while i + m <= n {
            if key[i] == query[0], key[i..<(i + m)].elementsEqual(query) {
                if i == 0 { return .prefix }
                if best != .wordPrefix, key[i - 1] == " " { best = .wordPrefix }
                else if best == nil { best = .substring }
            }
            i += 1
        }
        return best
    }
}
