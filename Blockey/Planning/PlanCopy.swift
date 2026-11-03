import Foundation

/// The words on the "Plan <day>" sheet that depend on counts, kept as pure functions so the
/// views only lay them out and the sentences can be tested. Foundation only, like the rest of
/// `Planning/`.
enum PlanCopy {

    private static func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

    /// "on Monday", but plain "today" and "tomorrow", which read badly after "on".
    static func on(_ dayPhrase: String) -> String {
        dayPhrase == "today" || dayPhrase == "tomorrow" ? dayPhrase : "on \(dayPhrase)"
    }

    /// Said wherever blocks are about to be deleted. A block with no token cannot be traced back
    /// to a task, so it cannot be put back in the inbox.
    static func untaggedLoss(count: Int) -> String {
        count == 1
            ? "One block has lost its Blockey tag, so it cannot be returned to the inbox. It will be deleted for good."
            : "\(count) blocks have lost their Blockey tag, so they cannot be returned to the inbox. They will be deleted for good."
    }

    /// "3 blocks · 1 moved to fit · 1 to your inbox"
    static func countLine(for preview: StampPreview) -> String {
        var parts = [plural(preview.confirmCount, "block")]
        let moved = preview.rows.filter { if case .moved = $0.kind { return true } else { return false } }.count
        if moved > 0 { parts.append("\(moved) moved to fit") }
        if preview.inboxCount > 0 { parts.append("\(preview.inboxCount) to your inbox") }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// The confirm button. `deleting` is how many blocks Start over removes, 0 in Keep.
    static func confirmTitle(for preview: StampPreview, deleting: Int, dayPhrase: String) -> String {
        if preview.isConfirmDisabled { return "Nothing fits" }
        if preview.mode == .startOver {
            return "Delete \(deleting) and add \(plural(preview.confirmCount, "block"))"
        }
        return "Add \(plural(preview.confirmCount, "block")) for \(dayPhrase)"
    }

    /// What Start over warns about, as separate sentences so the view can lay them out.
    ///
    /// `deleting` counts the editable own blocks the clear removes. `untagged` is the subset
    /// with no token. `kept` is the own blocks the clear leaves alone (repeating or multi-day).
    static func startOverWarnings(deleting: Int, untagged: Int, kept: Int, dayPhrase: String) -> [String] {
        var lines = [
            "Deletes \(plural(deleting, "block")) \(on(dayPhrase)), including any you placed by hand. "
                + "Blocks that came from your inbox go back to your inbox. Your meetings are not touched."
        ]
        if untagged > 0 { lines.append(untaggedLoss(count: untagged)) }
        if kept > 0 {
            lines.append(kept == 1
                         ? "1 repeating or multi-day block stays where it is."
                         : "\(kept) repeating or multi-day blocks stay where they are.")
        }
        return lines
    }

    /// Under a disabled confirm button.
    static func nothingFits(isToday: Bool) -> String {
        isToday ? "Your day is full from now on. Try tomorrow." : "Your meetings fill this day. Nothing fits."
    }

    static func zeroLength(count: Int) -> String {
        count == 1 ? "1 row has no length and was skipped." : "\(count) rows have no length and were skipped."
    }

    /// The inbox row's note for a task that fell out of a template.
    static func inboxNote(templateName: String?) -> String {
        "from \(templateName ?? "your template"), no room"
    }

    /// The Place-all button, and its reason when disabled.
    ///
    /// `fitting` is how many of the `count` open tasks fit on their own. When only some do, the
    /// button says so rather than promising all of them.
    static func placeAllTitle(count: Int, fitting: Int? = nil, dayPhrase: String) -> String {
        if let fitting, fitting > 0, fitting < count { return "Place what fits for \(dayPhrase)" }
        return count == 1 ? "Place 1 for \(dayPhrase)" : "Place all \(count) for \(dayPhrase)"
    }

    static func placeAllReason(isToday: Bool, dayPhrase: String) -> String {
        isToday ? "Nothing fits in the time you have left." : "Nothing fits \(on(dayPhrase))."
    }
}
