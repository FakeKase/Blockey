import Foundation

/// Side-by-side placement for things that happen at the same time.
///
/// Two meetings that overlap must both stay visible, so overlapping items are
/// grouped into clusters and each cluster is split into as many columns as its
/// busiest moment needs. A cluster ends the moment nothing is still running,
/// which keeps a single 8am–6pm event from narrowing the entire day.
enum TimelineLayout {

    struct Placed<T> {
        let item: T
        let column: Int
        let columnCount: Int
    }

    static func columns<T>(for items: [T], range: (T) -> TimeRange) -> [Placed<T>] {
        let sorted = items.sorted { range($0).start < range($1).start }

        var result: [Placed<T>] = []
        var cluster: [(item: T, column: Int)] = []
        var columnEnds: [Date] = []
        var clusterEnd: Date?

        func flushCluster() {
            let count = Swift.max(1, columnEnds.count)
            result.append(contentsOf: cluster.map { Placed(item: $0.item, column: $0.column, columnCount: count) })
            cluster.removeAll()
            columnEnds.removeAll()
            clusterEnd = nil
        }

        for item in sorted {
            let itemRange = range(item)

            // Nothing from the previous cluster is still running: start fresh.
            if let end = clusterEnd, itemRange.start >= end {
                flushCluster()
            }

            var assigned = false
            for index in columnEnds.indices where columnEnds[index] <= itemRange.start {
                columnEnds[index] = itemRange.end
                cluster.append((item, index))
                assigned = true
                break
            }
            if !assigned {
                columnEnds.append(itemRange.end)
                cluster.append((item, columnEnds.count - 1))
            }

            clusterEnd = Swift.max(clusterEnd ?? itemRange.end, itemRange.end)
        }

        flushCluster()
        return result
    }
}
