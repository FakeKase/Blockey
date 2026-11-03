import Foundation
import SwiftData

/// A day on which at least one block was added: the streak's only stored fact (issue #7).
///
/// Additive to the schema, so the existing store migrates lightly. Keyed by the Gregorian
/// `yyyy-MM-dd` string of a `CivilDay` and unique per day. Never deleted by Undo, Clear or delete,
/// because the day counts once the add happened.
///
/// Like tasks and templates, this is not in iCloud (ADR 003), so it travels in the backup.
@Model
final class ActivityDay {
    @Attribute(.unique) var key: String
    var recordedAt: Date

    init(key: String, recordedAt: Date = .now) {
        self.key = key
        self.recordedAt = recordedAt
    }
}
