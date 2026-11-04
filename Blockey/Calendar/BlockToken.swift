import Foundation

/// The only place in Blockey that knows how a block is tagged inside a calendar event.
///
/// `EKEvent` has no custom fields, so everything the app needs beyond title and
/// time rides in the event's `url`:
///
///     blockey://block/<uuid>?c=<category>&t=<source task uuid>
///
/// Two consequences worth stating, because they shaped the rest of the design:
///
/// **No EventKit identifier is ever persisted.** Blocks are always found by
/// fetching the Blockey calendar over a date range. Apple documents
/// `eventIdentifier` as changing when an event moves calendar or when a sync
/// re-creates it, and `calendarItemIdentifier` as not sync-proof — so the app
/// designs the problem out rather than defending against it.
///
/// **Losing the token is cosmetic.** If the user clears the URL field in
/// Calendar.app, or a CalDAV round trip normalises it away, the block still
/// appears and still works; it just falls back to a default colour and forgets
/// which inbox task it came from. Nothing breaks, nothing is duplicated.
struct BlockToken: Equatable, Sendable {
    static let scheme = "blockey"
    private static let host = "block"

    var id: UUID
    /// The slug exactly as stored in `c=`, NFC-normalised, or nil when there is no usable
    /// one. This, not `category`, is the source of truth: `BlockCategory` is a closed enum,
    /// so a slug the app doesn't know (a custom category, or text typed into Calendar.app)
    /// would otherwise collapse to the fallback here and be rewritten as that fallback on
    /// the next Save, losing the original for good.
    var categorySlug: String?
    var sourceTaskID: UUID?
    /// Query items we don't own, in the order they appeared. Written back untouched so a
    /// token edited in Calendar.app, or by a newer build, isn't stripped by an older one.
    private(set) var unknownQueryItems: [URLQueryItem]

    /// A copy with the slug replaced and everything else (id, source task, unknown query
    /// items) untouched. The update path uses this so an edit never mints a new identity.
    func replacingCategorySlug(_ slug: String?) -> BlockToken {
        var copy = self
        copy.categorySlug = Self.clean(slug)
        return copy
    }

    init(id: UUID = UUID(), category: BlockCategory = .fallback, sourceTaskID: UUID? = nil) {
        self.init(id: id, categorySlug: category.rawValue, sourceTaskID: sourceTaskID)
    }

    init(id: UUID = UUID(), categorySlug: String?, sourceTaskID: UUID? = nil) {
        self.id = id
        self.categorySlug = Self.clean(categorySlug)
        self.sourceTaskID = sourceTaskID
        self.unknownQueryItems = []
    }

    /// NFC so the same Thai text typed on two keyboards (or round-tripped through a
    /// client that decomposes) compares equal. Blank means absent: an empty `c=` carries
    /// no information and shouldn't be written back as if it did. Case is kept, since
    /// slugs are case-sensitive.
    private static func clean(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return raw.precomposedStringWithCanonicalMapping
    }

    /// Parses a token, returning nil for anything that is not ours — including
    /// a URL the user typed into the event by hand.
    init?(url: URL?) {
        // Scheme and host are case-insensitive per RFC 3986, and a round trip
        // through another calendar client may normalise their case. Comparing
        // them literally would throw the token away and lose the block's
        // colour and task link.
        guard let url,
              url.scheme?.lowercased() == Self.scheme,
              url.host?.lowercased() == Self.host,
              let id = UUID(uuidString: url.lastPathComponent)
        else { return nil }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        self.id = id
        // First `c` wins, even if it is blank: a later duplicate is not a fallback for it.
        self.categorySlug = Self.clean(value("c"))
        self.sourceTaskID = value("t").flatMap(UUID.init(uuidString:))
        self.unknownQueryItems = items.filter { $0.name != "c" && $0.name != "t" }
    }

    /// Nil only if URLComponents refuses the parts, which the fixed scheme, host and UUID path
    /// make effectively impossible. Optional rather than a placeholder url because a wrong url
    /// written to an event would destroy the id, category and task link, which is worse than
    /// writing nothing: callers leave the event's existing url alone on nil.
    var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.path = "/\(id.uuidString)"
        var items: [URLQueryItem] = []
        if let categorySlug {
            items.append(URLQueryItem(name: "c", value: categorySlug))
        }
        if let sourceTaskID {
            items.append(URLQueryItem(name: "t", value: sourceTaskID.uuidString))
        }
        items += unknownQueryItems
        components.queryItems = items.isEmpty ? nil : items
        return components.url
    }
}
