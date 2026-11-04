import SwiftUI

/// The editor's Emoji section (UI spec 3.2): the chosen glyph, a grid of suggestions and, on a
/// device that can draw emoji, a field to type one's own. The simulator cannot draw emoji, so
/// there the free-entry field is hidden (anything typed would only be a tofu box) and the grid
/// shows each suggestion's symbol.
struct CategoryEmojiSection: View {
    @Binding var draft: CategoryDraft
    /// Show the "Choose an emoji" message in place of the usual footer.
    let showsRequired: Bool

    @ScaledMetric(relativeTo: .title2) private var cell: CGFloat = 44
    @State private var typed = ""
    private let canTypeOwn = Emoji.isSupported

    var body: some View {
        Section {
            header
            LazyVGrid(columns: [GridItem(.adaptive(minimum: cell), spacing: 8)], spacing: 8) {
                ForEach(EmojiSuggestions.all, id: \.emoji) { suggestion in
                    suggestionCell(suggestion)
                }
            }
            .padding(.vertical, 4)
            if canTypeOwn {
                TextField("Type your own", text: Binding(get: { typed }, set: typeOwn))
                    .frame(minHeight: 44)
                    .accessibilityLabel("Type your own emoji")
            }
        } header: {
            Text("Emoji")
        } footer: {
            if showsRequired {
                Label { Text(CategoryEditorCopy.emojiRequired) } icon: {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                }
                .foregroundStyle(.primary)
            } else {
                Text(CategoryEditorCopy.emojiFooter(canTypeOwn: canTypeOwn))
            }
        }
    }

    private var style: CategoryStyle {
        CategoryStyle(title: draft.value.name, emoji: draft.value.emoji,
                      symbolName: draft.value.symbolName, colors: draft.colors)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Group {
                if draft.hasEmoji {
                    CategoryGlyph(style: style, size: .largeTitle, tinted: true)
                } else {
                    Image(systemName: "face.smiling").font(.title).foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 56)
            .background {
                if draft.hasEmoji {
                    RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05))
                } else {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(draft.hasEmoji
                                ? (EmojiSuggestions.label(for: draft.value.emoji) ?? draft.value.emoji)
                                : "No emoji chosen")
            Spacer(minLength: 0)
        }
        .frame(minHeight: 56)
    }

    private func suggestionCell(_ suggestion: EmojiSuggestions.Suggestion) -> some View {
        let selected = EmojiSuggestions.comparisonKey(draft.value.emoji) == EmojiSuggestions.comparisonKey(suggestion.emoji)
        return Button {
            draft.chooseEmoji(suggestion.emoji)
            typed = ""
        } label: {
            Group {
                if Emoji.isSupported {
                    Text(suggestion.emoji).font(.title2)
                } else {
                    Image(systemName: suggestion.symbolName).font(.title3).foregroundStyle(.primary)
                }
            }
            .frame(width: cell, height: cell)
            .overlay {
                if selected { Circle().strokeBorder(Color.accentColor, lineWidth: 2) }
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor, Color(uiColor: .systemBackground))
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(suggestion.label)
        .accessibilityValue(selected ? "Selected" : "")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// Keeps the last character typed so a new emoji replaces the old one; blank or invisible
    /// input is ignored (`isAcceptableEmoji`).
    private func typeOwn(_ text: String) {
        let last = EmojiEntry.lastCharacter(of: text)
        guard CategoryCatalog.isAcceptableEmoji(last) else { typed = ""; return }
        typed = last
        draft.chooseEmoji(last)
    }
}
