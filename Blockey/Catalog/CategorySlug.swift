import Foundation

/// Mints and reads category slugs. Pure and Foundation-only. See ADR 005, "Slugs".
///
/// A slug is what a block's token stores and the only thing a calendar event knows about its
/// category, so the rules here are a public format: they may change for new slugs, never for
/// ones already minted.
enum CategorySlug {

    /// Custom slugs start with this, and no built-in slug ever does, so a custom slug can never
    /// collide with a built-in added by a later version.
    static let customPrefix = "u-"

    /// The body is capped by grapheme cluster, so a Thai tone mark is never cut off its consonant.
    static let maxBodyClusters = 32

    /// Invisible characters that make a name look non-empty while saying nothing.
    static let invisibleScalars: Set<Unicode.Scalar> = ["\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{FEFF}"]

    private static let randomAlphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
    private static let randomLength = 6

    /// A slug for a new custom category, or nil when the name has nothing in it (empty,
    /// whitespace, or only invisible characters).
    ///
    /// `taken` must hold every existing slug, archived ones and the built-ins included
    /// (`CategoryCatalog.takenSlugs`): an archived category's blocks still carry its slug, so
    /// reusing it would silently merge two meanings. The random source is injected so the
    /// emoji-only path is testable.
    static func mint<R: RandomNumberGenerator>(name: String, taken: Set<String>,
                                               random: inout R) -> String? {
        guard hasContent(name) else { return nil }

        var body = normalisedBody(name)
        if body.isEmpty {
            // Letters and numbers are all that survive normalisation, so an emoji-only name has
            // nothing to say. A random body keeps it unique without pretending to be meaningful.
            body = String((0..<randomLength).map { _ in
                randomAlphabet[Int.random(in: 0..<randomAlphabet.count, using: &random)]
            })
        }

        let base = customPrefix + body
        if !taken.contains(base) { return base }
        // The suffix goes after the cap, so a long name can still be told apart from itself.
        var n = 2
        while taken.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }

    /// Best-effort name for a slug nobody has a definition for: drop `u-`, turn `-` into a space.
    /// Case, collapsed punctuation and whether `-2` was a collision suffix are all lost, so a real
    /// definition is always the better source.
    static func displayName(fromSlug slug: String) -> String {
        let body = slug.hasPrefix(customPrefix) ? String(slug.dropFirst(customPrefix.count)) : slug
        let name = body.replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // "u-" alone would read as a blank name; show the slug rather than nothing.
        return name.isEmpty ? slug : name
    }

    /// 32-bit FNV-1a over the UTF-8 bytes. Never Swift's `hashValue`, which is seeded per
    /// process: the same block would change colour on every launch. A test pins a slug to a
    /// hard-coded value for exactly that reason.
    static func fnv1a32(_ text: String) -> UInt32 {
        var hash: UInt32 = 0x811C_9DC5
        for byte in text.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x0100_0193
        }
        return hash
    }

    /// The palette slot of a slug nobody knows. `paletteCount` is injected so tests can pin the
    /// arithmetic at other sizes; callers pass `CategoryPalette.count`.
    static func standInPaletteIndex(for slug: String, paletteCount: Int) -> Int {
        guard paletteCount > 0 else { return 0 }
        // Widened before the modulo: `UInt32(paletteCount)` would trap for a count above 4 billion.
        return Int(UInt64(fnv1a32(slug)) % UInt64(paletteCount))
    }

    // MARK: Normalisation

    /// True when the name has at least one scalar that is neither whitespace nor invisible.
    static func hasContent(_ name: String) -> Bool {
        name.unicodeScalars.contains {
            !invisibleScalars.contains($0) && !$0.properties.isWhitespace
        }
    }

    /// NFKC, locale-independent lowercase, then one pass over grapheme clusters. A cluster whose
    /// base scalar is a letter or number is kept whole, combining marks included; anything else
    /// is a separator, runs collapse to one `-`, and the ends are trimmed.
    private static func normalisedBody(_ name: String) -> String {
        // NFKC rather than NFC so full-width Latin becomes ASCII, and so NFD and NFC input agree.
        let folded = name.precomposedStringWithCompatibilityMapping.lowercased()

        var clusters: [String] = []
        var pendingSeparator = false
        for ch in folded {
            if isLetterOrNumber(ch) {
                if pendingSeparator, !clusters.isEmpty { clusters.append("-") }
                pendingSeparator = false
                clusters.append(String(ch))
            } else {
                pendingSeparator = true
            }
        }

        var capped = Array(clusters.prefix(maxBodyClusters))
        while capped.last == "-" { capped.removeLast() }
        return capped.joined()
    }

    private static func isLetterOrNumber(_ ch: Character) -> Bool {
        guard let base = ch.unicodeScalars.first else { return false }
        switch base.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }
}
