import SwiftUI

/// The kind of work a block represents.
///
/// Deliberately a fixed enum rather than a user-editable SwiftData model.
/// Categories are identified by their raw slug, which is what travels inside a
/// block's token, so colours survive anything that happens to local storage —
/// there is no colour table to lose. Six buckets is enough to read a day at a
/// glance; more would just be a settings screen nobody opens.
enum BlockCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case deepWork = "deep"
    case meeting
    case admin
    case personal
    case health
    case rest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deepWork: return "Deep work"
        case .meeting:  return "Meeting"
        case .admin:    return "Admin"
        case .personal: return "Personal"
        case .health:   return "Health"
        case .rest:     return "Rest"
        }
    }

    var symbolName: String {
        switch self {
        case .deepWork: return "brain.head.profile"
        case .meeting:  return "person.2.fill"
        case .admin:    return "tray.full.fill"
        case .personal: return "house.fill"
        case .health:   return "figure.run"
        case .rest:     return "cup.and.saucer.fill"
        }
    }

    var tint: Color {
        switch self {
        case .deepWork: return Color(red: 0.29, green: 0.40, blue: 0.87)
        case .meeting:  return Color(red: 0.85, green: 0.42, blue: 0.24)
        case .admin:    return Color(red: 0.45, green: 0.48, blue: 0.56)
        case .personal: return Color(red: 0.36, green: 0.64, blue: 0.42)
        case .health:   return Color(red: 0.83, green: 0.33, blue: 0.51)
        case .rest:     return Color(red: 0.52, green: 0.44, blue: 0.72)
        }
    }

    static let fallback: BlockCategory = .deepWork
}
