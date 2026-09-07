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
    var category: BlockCategory
    var sourceTaskID: UUID?

    init(id: UUID = UUID(), category: BlockCategory = .fallback, sourceTaskID: UUID? = nil) {
        self.id = id
        self.category = category
        self.sourceTaskID = sourceTaskID
    }

    /// Parses a token, returning nil for anything that is not ours — including
    /// a URL the user typed into the event by hand.
    init?(url: URL?) {
        guard let url,
              url.scheme == Self.scheme,
              url.host == Self.host,
              let id = UUID(uuidString: url.lastPathComponent)
        else { return nil }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        self.id = id
        self.category = value("c").flatMap(BlockCategory.init(rawValue:)) ?? .fallback
        self.sourceTaskID = value("t").flatMap(UUID.init(uuidString:))
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.path = "/\(id.uuidString)"
        var items = [URLQueryItem(name: "c", value: category.rawValue)]
        if let sourceTaskID {
            items.append(URLQueryItem(name: "t", value: sourceTaskID.uuidString))
        }
        components.queryItems = items
        // The components above are all well-formed by construction.
        return components.url ?? URL(string: "\(Self.scheme)://\(Self.host)/\(id.uuidString)")!
    }
}
