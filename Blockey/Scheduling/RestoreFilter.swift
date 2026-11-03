import Foundation

/// Which blocks Undo may write back, given the fixed events on the day right now.
///
/// Pure, like the rest of `Scheduling/`: Undo recreates blocks at their original times, and
/// the headline rule is that fixed events always win. A meeting that arrived since the block was
/// cleared is not moved around; the block is simply not written, and Undo says so.
enum RestoreFilter {

    /// Splits `candidates` by index into those clear of every fixed range and those that
    /// overlap one. Ranges are half-open, so a block that merely touches a meeting is fine.
    /// Both lists keep the input order.
    static func split(_ candidates: [TimeRange],
                      avoiding fixed: [TimeRange]) -> (writable: [Int], blocked: [Int]) {
        var writable: [Int] = []
        var blocked: [Int] = []
        for (index, range) in candidates.enumerated() {
            if fixed.contains(where: { $0.overlaps(range) }) {
                blocked.append(index)
            } else {
                writable.append(index)
            }
        }
        return (writable, blocked)
    }
}
