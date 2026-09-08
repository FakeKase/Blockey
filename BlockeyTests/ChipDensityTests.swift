import Testing
import Foundation
import CoreGraphics
@testable import Blockey

/// The rule that stops a block drawing outside its own time.
///
/// A chip that will not fit its slot used to overflow it: a flexible frame
/// sizes itself to its content when the content refuses to shrink, and the
/// rigid frame outside then centred the oversized chip, spilling it several
/// points into the blocks above and below. A 30-minute block was the smallest
/// one the stacked layout could not fit, which is why an evening of half-hour
/// blocks looked overlapped.
///
/// These pin the durations to the layout each one gets, in the units the
/// timeline actually uses: 64 points to the hour.
@Suite("Chip density")
struct ChipDensityTests {

    private let hourHeight: CGFloat = 64

    private func density(minutes: Int) -> ChipDensity {
        ChipDensity(height: CGFloat(minutes) / 60 * hourHeight)
    }

    @Test("An hour is roomy enough to stack the time under the title")
    func hourIsFull() {
        #expect(density(minutes: 60) == .full)
        #expect(density(minutes: 90) == .full)
        #expect(density(minutes: 45) == .full)
    }

    @Test("Half an hour puts the title and time on one line")
    func halfHourIsSingleLine() {
        // The regression: 30 minutes is 32pt, and the stacked layout needs 41.
        #expect(density(minutes: 30) == .single)
    }

    @Test("A quarter of an hour has room for the title alone")
    func quarterHourIsTitleOnly() {
        #expect(density(minutes: 15) == .titleOnly)
    }

    @Test("Density never grows as a block gets shorter")
    func monotonic() {
        let order: [ChipDensity: Int] = [.titleOnly: 0, .single: 1, .full: 2]
        var previous = 0
        for minutes in stride(from: 5, through: 240, by: 5) {
            let rank = order[density(minutes: minutes)]!
            #expect(rank >= previous, "density went backwards at \(minutes) minutes")
            previous = rank
        }
    }

    @Test("A chip is only allowed a layout its own height can hold")
    func layoutFitsWithinTheSlot() {
        // Measured minimums for the three layouts, including vertical padding.
        let required: [ChipDensity: CGFloat] = [.full: 41, .single: 22, .titleOnly: 18]
        // 20pt is the floor the timeline gives even a very short block.
        for height in stride(from: CGFloat(20), through: 300, by: 1) {
            let chosen = ChipDensity(height: height)
            #expect(required[chosen]! <= height,
                    "\(chosen) needs \(required[chosen]!)pt but was chosen at \(height)pt")
        }
    }
}

@Suite("Block time labels")
struct TimeRangeTextTests {

    /// Both ends of the range are shown — the end time is the whole point.
    ///
    /// The label is formatted for whoever is reading it, so the test builds its
    /// date in the same calendar the formatter will use. Pinning the date to
    /// UTC and the expectation to "21" would only be testing the machine's
    /// timezone.
    @Test("A range names its start and its end")
    func showsBothEnds() {
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: .now)!
        let range = TimeRange(start: start, duration: 30 * 60)
        let text = timeRangeText(range)

        let hour = calendar.component(.hour, from: start)
        #expect(text.contains("\(hour)") || text.contains("\(hour % 12)"))
        #expect(text.contains("30"), "the end time is missing from \(text)")
        // A separator, so the two times cannot be read as one.
        #expect(text.contains("–") || text.contains("-") || text.contains("—"))
    }
}
