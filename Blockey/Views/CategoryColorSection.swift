import SwiftUI
import UIKit

/// The editor's Colour section (UI spec 3.3, task 3.8b): twelve swatches in picker order, the
/// `Other...` row, a light and a dark preview on the canvas colours, one warning line and the
/// derived-brightness note. Judged against `ColorSurfaces.assumedPendingStory1` until Story 1
/// publishes real surfaces; that is one declaration to change.
struct CategoryColorSection: View {
    @Binding var draft: CategoryDraft
    let catalog: CategoryCatalog

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var swatchSide: CGFloat = 44
    /// Set only by a pick in the system colour picker, so the warning is announced after that and
    /// never for a palette tap or on opening the editor.
    @State private var pickedCustom = false

    private let surfaces = ColorSurfaces.assumedPendingStory1

    var body: some View {
        let line = draft.warningLine(in: catalog, surfaces: surfaces)
        Section {
            swatchGrid
            otherRow
            previews
            if let line {
                Label { Text(line).font(.footnote) } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .foregroundStyle(.primary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ColorConcernCopy.spoken(line))
            }
        } header: {
            Text("Colour")
        } footer: {
            if draft.usesCustomColor { Text(ColorConcernCopy.derivedNote) }
        }
        // Debounced one second after the last pick, so dragging in the picker is not read aloud.
        .task(id: AnnouncementKey(hex: draft.value.customColorHex, line: line)) {
            guard pickedCustom, draft.usesCustomColor, let line else { return }
            try? await _Concurrency.Task.sleep(for: .seconds(1))
            guard !_Concurrency.Task.isCancelled else { return }
            AccessibilityNotification.Announcement(ColorConcernCopy.spoken(line)).post()
        }
    }

    private struct AnnouncementKey: Hashable { var hex: String?; var line: String? }

    // MARK: Swatches

    private var swatchGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: swatchSide), spacing: 12)], spacing: 12) {
            ForEach(Array(CategoryPalette.pickerOrder.enumerated()), id: \.element) { position, index in
                swatch(index: index, position: position + 1)
            }
        }
        .padding(.vertical, 4)
    }

    private func swatch(index: Int, position: Int) -> some View {
        let swatch = CategoryPalette.swatches[index]
        let style = CategoryStyle(title: swatch.name, emoji: "", symbolName: "", colors: swatch.colors)
        let selected = draft.selectedPaletteIndex == index
        return Button {
            draft.choosePalette(index)
            pickedCustom = false
        } label: {
            Circle()
                .fill(style.spine)
                .frame(width: swatchSide - 8, height: swatchSide - 8)
                .overlay {
                    if selected {
                        Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(style.onFill)
                    }
                }
                .padding(4)
                .overlay { if selected { Circle().strokeBorder(Color.accentColor, lineWidth: 3) } }
                .frame(width: swatchSide, height: swatchSide)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CategoryEditorCopy.swatchLabel(name: swatch.name, position: position,
                                                           total: CategoryPalette.pickerOrder.count))
        .accessibilityValue(selected ? "Selected" : "")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Other...

    private var otherRow: some View {
        let custom = draft.usesCustomColor
        return ColorPicker(selection: pickerBinding, supportsOpacity: false) {
            HStack(spacing: 8) {
                if custom { Image(systemName: "checkmark").foregroundStyle(Color.accentColor).accessibilityHidden(true) }
                Image(systemName: "paintpalette").accessibilityHidden(true)
                Text("Other\u{2026}")
                Spacer(minLength: 8)
                if custom { Text("Custom").foregroundStyle(.secondary) }
            }
        }
        .frame(minHeight: 44)
        .accessibilityLabel("Other colour")
        .accessibilityValue(custom ? "Selected" : "")
        .accessibilityHint("Opens the colour picker")
    }

    /// Opens on the custom colour when there is one, else near the swatch in use. Only a real
    /// change in the system picker calls `set`, which is what selects the row: merely opening the
    /// picker leaves the swatch selected.
    private var pickerBinding: Binding<Color> {
        Binding(
            get: {
                if case .custom(let hex) = draft.colorChoice, let c = SRGB(hex: hex) { return c.color }
                return draft.colors.light.spine.color
            },
            set: { picked in
                // Display P3 picks can fall outside sRGB; `SRGB.hex` clamps each channel to 0...1.
                guard let hex = Self.hex(from: picked) else { return }
                if draft.chooseCustom(hex: hex) { pickedCustom = true }
            })
    }

    static func hex(from color: Color) -> String? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return SRGB(r: Double(r), g: Double(g), b: Double(b)).hex
    }

    // MARK: Previews

    private var previews: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                                                  : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            preview(isDark: false)
            preview(isDark: true)
        }
        .padding(.vertical, 4)
    }

    private func preview(isDark: Bool) -> some View {
        let record = draft.colors.record(isDark: isDark)
        let canvas = surfaces.mode(isDark: isDark).canvas
        let name = CategoryCatalog.cleanedName(draft.value.name)
        let title = isDark ? "Dark" : "Light"
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            HStack(spacing: 0) {
                Rectangle().fill(record.spine.color).frame(width: 3)
                HStack(spacing: 6) {
                    glyph(record)
                    Text(name.isEmpty ? "Name" : name)
                        .font(.footnote)
                        .foregroundStyle(record.onFill.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(record.fill.color)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(record.border.color, lineWidth: 1))
            .padding(12)
            .background(canvas.color, in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview in \(isDark ? "dark" : "light") mode")
        .accessibilityValue(name.isEmpty ? "Name" : name)
    }

    /// Explicit colours, never semantic ones: the dark patch must stay dark on a light phone.
    @ViewBuilder
    private func glyph(_ record: CategoryColorRecord) -> some View {
        if draft.hasEmoji {
            if Emoji.isSupported {
                Text(draft.value.emoji).font(.footnote)
            } else {
                Image(systemName: draft.value.symbolName).font(.footnote).foregroundStyle(record.spine.color)
            }
        }
    }
}
