import Foundation

/// When to warn that this build is about to stop launching.
///
/// A free-provisioned app stops opening after seven days, and the failure is
/// silent: no warning, no prompt, just a phone that refuses on an ordinary
/// Tuesday. That is a worse problem than it sounds, because a planning habit
/// takes about three weeks to set and the certificate gives you one.
///
/// The reminder has to arrive *after* the app can no longer be opened, which
/// rules out anything living in the app — a local notification goes with the
/// sandbox. A calendar event with an alarm does not: it is already outside the
/// app, already on the Lock Screen and the Watch, and needs no notification
/// permission. See `CalendarService.ensureSigningReminder`.
///
/// Pure by design: the dates are decided here and tested, and only the writing
/// touches EventKit.
enum SigningReminder {

    /// The title the event is found by, so running twice does not make two.
    /// Stable on purpose — anything date-dependent would break the match.
    static let title = "Re-sign Blockey"

    /// Scheme and host of the marker written to the reminder's `url`.
    private static let markerScheme = "blockey"
    private static let markerHost = "signing-reminder"

    /// What the reminder carries in its `url`. The title alone cannot identify it,
    /// because the user can name a block anything, including this. The host is
    /// deliberately not `block`, so `BlockToken(url:)` rejects it and the reminder
    /// can never be read as a block (and a block can never match here).
    static let markerURL = URL(string: "blockey://signing-reminder")

    /// Whether a url is the reminder marker. Case-insensitive like BlockToken:
    /// another client may normalise scheme and host.
    static func isMarked(url: URL?) -> Bool {
        url?.scheme?.lowercased() == markerScheme && url?.host?.lowercased() == markerHost
    }

    /// Whether an event is our reminder, so cleanup touches nothing else.
    ///
    /// The marker is authoritative. The fallback exists for reminders written
    /// before the marker did: those are all-day with exactly this title and no
    /// url. Requiring no url means any other url (a block token, a meeting link)
    /// marks the event as someone's own, so it needs no dependency on BlockToken.
    static func isReminder(title: String?, isAllDay: Bool, url: URL?) -> Bool {
        if isMarked(url: url) { return true }
        return url == nil && isAllDay && title == Self.title
    }

    /// Only short-lived profiles need warning about. A paid account's profile
    /// lasts a year, and a reminder eleven months out is noise.
    static let horizon: TimeInterval = 30 * 86_400

    /// Two days' notice: enough to find a moment at a Mac, short enough that the
    /// reminder is still about this week.
    static let leadTime: TimeInterval = 2 * 86_400

    /// Evening, when someone is more likely to be near their computer than at
    /// 9am on the way out.
    static let alarmHour = 19

    /// The day to put the reminder on, or `nil` when one is not warranted.
    ///
    /// Returns `nil` for a profile that has already expired (the app could not
    /// be running) and for one too far out to be free-provisioned.
    static func day(expiring expiry: Date, now: Date, calendar: Calendar = .current) -> Date? {
        guard expiry > now else { return nil }
        guard expiry.timeIntervalSince(now) <= horizon else { return nil }

        // With less than the lead time left, the reminder is for today rather
        // than for a day that has already gone.
        let target = max(expiry.addingTimeInterval(-leadTime), now)
        return calendar.startOfDay(for: target)
    }

    /// When the alarm fires on that day.
    ///
    /// Clamped to the near future, because an alarm set for 7pm when it is
    /// already 10pm would never go off at all. Opening the app late on the day
    /// the warning is due therefore produces one almost immediately — which is
    /// the right outcome rather than a bug: the user is holding the phone, and
    /// the alternative is silence until the app stops opening.
    static func alarmDate(on day: Date, now: Date, calendar: Calendar = .current) -> Date {
        let evening = calendar.date(bySettingHour: alarmHour, minute: 0, second: 0, of: day) ?? day
        return max(evening, now.addingTimeInterval(60))
    }

    /// What the event says when opened. The title is the instruction; this is
    /// the detail, including the date the app actually stops.
    static func notes(expiry: Date) -> String {
        """
        Blockey stops launching on \(expiry.formatted(date: .complete, time: .shortened)).

        Connect this iPhone to your Mac, open Blockey.xcodeproj and press Run. \
        Your blocks are calendar events and are safe either way; tasks and \
        templates live only on the phone, so export a backup from Settings if \
        you have not lately.
        """
    }
}
