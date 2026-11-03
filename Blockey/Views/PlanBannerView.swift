import SwiftUI

/// One message on the Today screen, and the one thing it may offer to reverse.
///
/// The `UndoRecord` lives only here. Replacing the banner drops it, which is the intended
/// lifetime: Undo is for "what I just did", not for last hour.
struct PlanBanner: Identifiable, Equatable {
    enum Action: Equatable {
        /// Tapping the banner opens the inbox, where the rows that did not fit went.
        case openInbox
    }

    let id = UUID()
    let text: String
    var isWarning = false
    /// Only set when the record has something to undo.
    var undo: UndoRecord?
    var action: Action?
    /// Shown as the result of an Undo, which lingers a little longer than a plain success.
    var afterUndo = false

    init(text: String, isWarning: Bool = false, undo: UndoRecord? = nil,
         action: Action? = nil, afterUndo: Bool = false) {
        self.text = text
        self.isWarning = isWarning
        self.undo = undo?.hasEffect == true ? undo : nil
        self.action = action
        self.afterUndo = afterUndo
    }

    /// How long it stays when nothing is holding it open.
    ///
    /// Warnings linger because an error that disappears in 2.6 seconds may as well not have
    /// been shown. A banner with an Undo button gets longer than a plain success, because
    /// reaching for it takes a moment.
    var lifetime: TimeInterval {
        if isWarning { return 7 }
        if undo != nil { return 6 }
        if afterUndo { return 4 }
        return 2.6
    }

    /// The same banner without its tap action, for the inbox tray, where "open your inbox"
    /// has nowhere to go. Keeps the id (so the timer and announcement are not restarted) and
    /// the record (so Undo still works there).
    var withoutAction: PlanBanner {
        var copy = self
        copy.action = nil
        return copy
    }

    /// What Undo will do, for VoiceOver.
    var undoHint: String {
        guard let undo else { return "" }
        if undo.cleared != nil { return "Brings back the blocks you started over" }
        if !undo.placements.isEmpty { return "Puts the tasks back in your inbox" }
        return "Reverses what was just added"
    }
}

/// The banner itself. Shared by Today and the inbox tray (the tray covers Today, so without a
/// copy there Fill day's Undo would be hidden under the sheet).
///
/// Material-backed with a symbol and primary text rather than coloured text: orange text
/// failed contrast (design review M5/S4), and colour is never the only signal here.
struct PlanBannerView: View {
    let banner: PlanBanner
    var onUndo: () -> Void
    var onDismiss: () -> Void
    var onAction: () -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverRunning
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 4))

        layout {
            message
            if banner.undo != nil {
                Button(action: onUndo) {
                    Text("Undo")
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityHint(banner.undoHint)
            }
            // The timer is off under VoiceOver, so the message needs a way out.
            if voiceOverRunning {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11))
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape, onDismiss)
        // Announced once per banner by TodayView, not here: this view reappears when the inbox
        // tray opens, and that must not read the same message again.
    }

    private var message: some View {
        Button(action: banner.action == nil ? onDismiss : onAction) {
            HStack(spacing: 7) {
                Image(systemName: banner.isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(banner.isWarning ? Color.orange : Color.green)
                    .accessibilityHidden(true)
                Text(banner.text)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if banner.action != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 9)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel((banner.isWarning ? "Warning. " : "") + banner.text)
        .accessibilityHint(banner.action == nil ? "Dismisses this message" : "Opens your inbox")
    }
}
