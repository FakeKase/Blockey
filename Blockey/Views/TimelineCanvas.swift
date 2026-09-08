import SwiftUI

/// The day, drawn top to bottom.
///
/// One point of geometry underpins everything: `y(for:)` and `date(atY:)` are
/// exact inverses, so a block dragged N points moves by exactly the time N
/// points represents. Every interaction is expressed through those two.
///
/// The hour grid is laid out for real — a `VStack` of fixed-height rows — while
/// blocks are drawn as an overlay positioned by offset. That split matters:
/// `.offset` shifts only *rendering*, so a view moved with it keeps a layout
/// frame at the top of the scroll content and `scrollTo` would jump to the top
/// of the day instead of to now. The hour rows carry the scroll anchors.
struct TimelineCanvas: View {

    let visible: TimeRange
    let window: TimeRange
    let blocks: [Block]
    let fixed: [Block]
    /// Gaps large enough to hold the armed task. Empty when nothing is armed.
    let candidateGaps: [TimeRange]
    let armedDuration: TimeInterval?
    let now: Date
    let snapMinutes: Int
    let calendar: Calendar

    var onSelectBlock: (Block) -> Void
    var onPlace: (Date) -> Void
    var onMove: (Block, TimeRange) -> Void

    @State private var drag: DragState?

    private let hourHeight: CGFloat = 64
    private let gutterWidth: CGFloat = 52
    private let minimumBlockHeight: CGFloat = 24

    private struct DragState: Equatable {
        enum Mode { case move, resize }
        let id: String
        let mode: Mode
        var offset: CGFloat
    }

    // MARK: Geometry

    private func y(for date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(visible.start) / 3600) * hourHeight
    }

    private func date(atY y: CGFloat) -> Date {
        visible.start.addingTimeInterval(TimeInterval(y / hourHeight * 3600))
    }

    private func height(for range: TimeRange) -> CGFloat {
        CGFloat(range.duration / 3600) * hourHeight
    }

    private var hourMarks: [Date] {
        var marks: [Date] = []
        var cursor = calendar.flooredToHour(visible.start)
        while cursor < visible.end {
            marks.append(cursor)
            cursor = cursor.addingTimeInterval(3600)
        }
        return marks
    }

    /// The hour row the day should open on.
    private var anchorHour: Date? {
        let clamped = min(max(now, visible.start), visible.end.addingTimeInterval(-1))
        return hourMarks.last { $0 <= clamped } ?? hourMarks.first
    }

    // MARK: Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                hourGrid
                    .overlay(alignment: .topLeading) { overlays }
                    .padding(.bottom, 150)
            }
            .onAppear { scrollToNow(proxy, animated: false) }
            .onChange(of: visible) { _, _ in scrollToNow(proxy, animated: true) }
            .sensoryFeedback(.impact(weight: .light), trigger: drag?.id)
        }
    }

    private func scrollToNow(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let anchorHour else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(anchorHour, anchor: .center) }
        } else {
            proxy.scrollTo(anchorHour, anchor: .center)
        }
    }

    // MARK: Grid

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(hourMarks, id: \.self) { mark in
                HStack(alignment: .top, spacing: 8) {
                    Text(mark, format: .dateTime.hour())
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .frame(width: gutterWidth - 8, alignment: .trailing)
                        .offset(y: -5)
                    Rectangle()
                        .fill(Color.primary.opacity(0.07))
                        .frame(height: 1)
                }
                .frame(height: hourHeight, alignment: .top)
                .id(mark)
            }
        }
    }

    /// Everything positioned by time rather than by stack order.
    private var overlays: some View {
        GeometryReader { geo in
            let contentWidth = geo.size.width - gutterWidth

            ZStack(alignment: .topLeading) {
                outOfWindowShading(width: contentWidth)
                gapLayer(width: contentWidth)
                scheduleLayer(width: contentWidth)
                nowIndicator(width: geo.size.width)
            }
        }
    }

    /// Dims hours outside the planning window without hiding them — an early
    /// meeting still has to be visible, just clearly out of bounds.
    private func outOfWindowShading(width: CGFloat) -> some View {
        ForEach(outsideWindow, id: \.start) { range in
            Rectangle()
                .fill(Color.primary.opacity(0.04))
                .frame(width: width, height: height(for: range))
                .offset(x: gutterWidth, y: y(for: range.start))
                .allowsHitTesting(false)
        }
    }

    private var outsideWindow: [TimeRange] {
        var ranges: [TimeRange] = []
        if visible.start < window.start {
            ranges.append(TimeRange(start: visible.start, end: window.start))
        }
        if window.end < visible.end {
            ranges.append(TimeRange(start: window.end, end: visible.end))
        }
        return ranges
    }

    private func gapLayer(width: CGFloat) -> some View {
        ForEach(candidateGaps, id: \.start) { gap in
            let duration = armedDuration ?? 0
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor.opacity(0.5),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                )
                .overlay(alignment: .top) {
                    Text("Tap to place")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 5)
                        .opacity(height(for: gap) > 34 ? 1 : 0)
                }
                .frame(width: width - 8, height: max(minimumBlockHeight, height(for: gap)))
                .offset(x: gutterWidth + 4, y: y(for: gap.start))
                .contentShape(Rectangle())
                .accessibilityElement()
                .accessibilityLabel("Free slot")
                .accessibilityValue(Text(gap.start, format: .dateTime.hour().minute()))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    onPlace(DaySchedule.snap(gap.start, toMinutes: snapMinutes, calendar: calendar))
                }
                .gesture(
                    SpatialTapGesture().onEnded { value in
                        // Snap first, then clamp — never the other way round.
                        // Clamping last is what guarantees the block stays
                        // inside the gap: a gap starting at 10:50 would
                        // otherwise snap back to 10:45 and overlap the meeting
                        // that just ended.
                        let tapped = date(atY: y(for: gap.start) + value.location.y)
                        let snapped = DaySchedule.snap(tapped, toMinutes: snapMinutes, calendar: calendar)
                        let latestStart = gap.end.addingTimeInterval(-duration)
                        onPlace(min(max(snapped, gap.start), max(gap.start, latestStart)))
                    }
                )
        }
    }

    /// Meetings and blocks share one column system.
    ///
    /// Laying them out separately would let a block dragged over a meeting draw
    /// on top of it — the two must compete for the same horizontal space to
    /// stay readable, exactly as they would in Calendar.
    private func scheduleLayer(width: CGFloat) -> some View {
        ForEach(TimelineLayout.columns(for: fixed + blocks, range: \.range), id: \.item.id) { placed in
            let item = placed.item
            let slot = columnFrame(placed: placed, width: width)

            Group {
                if item.isFixed {
                    FixedEventChip(block: item)
                        .frame(width: slot.width, height: max(minimumBlockHeight, height(for: item.range)))
                        .offset(x: gutterWidth + slot.x, y: y(for: item.range.start))
                } else {
                    blockView(item, slot: slot)
                }
            }
        }
    }

    private func blockView(_ block: Block, slot: (x: CGFloat, width: CGFloat)) -> some View {
        let isDragging = drag?.id == block.id
        let moveOffset = (isDragging && drag?.mode == .move) ? (drag?.offset ?? 0) : 0
        let growth = (isDragging && drag?.mode == .resize) ? (drag?.offset ?? 0) : 0
        let chipHeight = max(minimumBlockHeight, height(for: block.range) + growth)

        return BlockChip(block: block, isDragging: isDragging)
            .frame(width: slot.width, height: chipHeight)
            .overlay(alignment: .bottom) {
                if block.isEditable { resizeGrabber(for: block) }
            }
            .offset(x: gutterWidth + slot.x, y: y(for: block.range.start) + moveOffset)
            .zIndex(isDragging ? 10 : 1)
            .onTapGesture { onSelectBlock(block) }
            // A repeating or all-day event shares one identifier across every
            // occurrence, so dragging this one would rewrite a different one.
            .gesture(moveGesture(for: block), isEnabled: block.isEditable)
    }

    private func columnFrame(placed: TimelineLayout.Placed<Block>, width: CGFloat) -> (x: CGFloat, width: CGFloat) {
        let inset: CGFloat = 4
        let usable = width - inset * 2
        let columnWidth = usable / CGFloat(placed.columnCount)
        return (inset + columnWidth * CGFloat(placed.column), columnWidth - 2)
    }

    private func nowIndicator(width: CGFloat) -> some View {
        Group {
            if visible.contains(now) {
                HStack(spacing: 0) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                    Rectangle()
                        .fill(Color.red)
                        .frame(height: 1.5)
                }
                .frame(width: max(0, width - gutterWidth + 8), alignment: .leading)
                .offset(x: gutterWidth - 4, y: y(for: now) - 3.5)
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: Gestures

    /// Long-press to pick a block up, then drag.
    ///
    /// A plain drag gesture here would fight the enclosing ScrollView: blocks
    /// can cover most of the day, so any scroll that happens to start on one
    /// would move the block instead of scrolling. Requiring a press first is
    /// what Calendar does, and it makes the two gestures unambiguous.
    private func moveGesture(for block: Block) -> some Gesture {
        LongPressGesture(minimumDuration: 0.28)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                if case .second(true, let move?) = value {
                    drag = DragState(id: block.id, mode: .move, offset: move.translation.height)
                }
            }
            .onEnded { value in
                defer { drag = nil }
                guard case .second(true, let move?) = value else { return }
                let shift = TimeInterval(move.translation.height / hourHeight * 3600)
                let moved = DaySchedule.snap(block.range.start.addingTimeInterval(shift),
                                             toMinutes: snapMinutes,
                                             calendar: calendar)
                // Unclamped, a hard drag upward pushes the block into
                // yesterday: it saves successfully and then vanishes, because
                // the timeline only ever fetches the selected day.
                let latest = visible.end.addingTimeInterval(-block.range.duration)
                let bounded = min(max(moved, visible.start), max(visible.start, latest))
                guard bounded != block.range.start else { return }
                onMove(block, TimeRange(start: bounded, duration: block.range.duration))
            }
    }

    /// The grab bar for changing a block's length. Higher priority than the
    /// move gesture underneath it, or dragging the bottom edge would slide the
    /// whole block instead of stretching it.
    private func resizeGrabber(for block: Block) -> some View {
        Capsule()
            .fill(block.category.tint.opacity(0.55))
            .frame(width: 26, height: 3)
            .padding(.bottom, 3)
            .contentShape(Rectangle().inset(by: -10))
            .highPriorityGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        drag = DragState(id: block.id, mode: .resize, offset: value.translation.height)
                    }
                    .onEnded { value in
                        defer { drag = nil }
                        let change = TimeInterval(value.translation.height / hourHeight * 3600)
                        let rawEnd = block.range.end.addingTimeInterval(change)
                        let snapped = DaySchedule.snap(rawEnd, toMinutes: snapMinutes, calendar: calendar)
                        // Never let a block collapse to nothing.
                        let floor = block.range.start.addingTimeInterval(TimeInterval(snapMinutes * 60))
                        let end = min(max(snapped, floor), max(floor, visible.end))
                        guard end != block.range.end else { return }
                        onMove(block, TimeRange(start: block.range.start, end: end))
                    }
            )
    }
}

// MARK: - Chips

private struct BlockChip: View {
    let block: Block
    var isDragging: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tint = block.category.tint
        // Six categories cannot be told apart by hue alone — under deuteranopia
        // the closest pair stays below the threshold of noticing however the
        // palette is tuned. The symbol is what actually distinguishes them.
        HStack(alignment: .top, spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: 3)
            Image(systemName: block.category.symbolName)
                .font(.caption2)
                .foregroundStyle(tint)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(block.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                Text(block.range.start, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tint.opacity(scheme == .dark ? 0.30 : 0.17), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(scheme == .dark ? 0.7 : 0.45), lineWidth: 1))
        .shadow(color: .black.opacity(isDragging ? 0.18 : 0), radius: isDragging ? 8 : 0, y: isDragging ? 4 : 0)
        .scaleEffect(isDragging ? 1.02 : 1)
        .animation(.snappy(duration: 0.18), value: isDragging)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(block.title), \(block.category.title)")
        .accessibilityValue(Text(block.range.start, format: .dateTime.hour().minute()))
    }
}

private struct FixedEventChip: View {
    let block: Block

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(.secondary.opacity(0.5))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(block.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
                Text(block.range.start, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Kept quieter than a block in both schemes. In dark mode a plain
        // white overlay would make meetings the brightest thing on screen,
        // inverting the hierarchy: the day you planned should out-read the
        // day that was booked for you.
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(scheme == .dark ? 0.06 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(scheme == .dark ? 0.18 : 0.13),
                              style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(block.title), meeting, not movable")
        .accessibilityValue(Text(block.range.start, format: .dateTime.hour().minute()))
    }
}
