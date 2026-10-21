import Foundation
import CoreGraphics

nonisolated struct ReachVertex: Codable, Sendable {
    let x: Double
    let y: Double
}

nonisolated struct ReachRegion: Codable, Sendable {
    let anchor: ReachVertex
    let contours: [[ReachVertex]]
}

nonisolated struct ReachProfile: Codable, Sendable {
    let hand: String
    let landscape: Bool
    let centerX: Double
    let centerY: Double
    let compact: Bool
    let coverage: Double
    var regions: [ReachRegion]? = nil
    var referenceWidth: Double? = nil
    var referenceHeight: Double? = nil

    nonisolated func rect(in size: CGSize) -> CGRect {
        if let regions, !regions.isEmpty {
            let vertices = regions.flatMap { $0.contours.flatMap { $0 } }
            let xs = vertices.map { $0.x * size.width }
            let ys = vertices.map { $0.y * size.height }
            if let left = xs.min(), let right = xs.max(), let top = ys.min(), let bottom = ys.max() {
                return CGRect(x: left, y: top, width: right - left, height: bottom - top)
            }
        }
        let width = min(compact ? 208.0 : 288.0, max(0, size.width - 24))
        let height = min(compact ? 218.0 : 304.0, max(0, size.height - 24))
        let x = min(max(12, size.width * centerX - width / 2), max(12, size.width - width - 12))
        let y = min(max(12, size.height * centerY - height / 2), max(12, size.height - height - 12))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Do not scale measured touch targets down to fit a different window size.
    nonisolated func matches(_ size: CGSize) -> Bool {
        guard landscape == (size.width > size.height) else { return false }
        guard let referenceWidth, let referenceHeight else { return true }
        return abs(referenceWidth - size.width) < 2 && abs(referenceHeight - size.height) < 2
    }
}

/// Fits connected touch regions to the traced band, rather than fitting a rectangular panel.
nonisolated enum ReachEstimator {
    private nonisolated struct Cell: Hashable {
        let x: Int
        let y: Int
        var neighbors: [Cell] { [Cell(x: x - 1, y: y), Cell(x: x + 1, y: y), Cell(x: x, y: y - 1), Cell(x: x, y: y + 1)] }
    }

    nonisolated static func suggestedHand(strokes: [[CGPoint]], size: CGSize) -> String? {
        guard size.width > 0, strokes.count >= 2 else { return nil }
        let starts = strokes.compactMap(\.first).map { $0.x / size.width }.sorted()
        guard !starts.isEmpty else { return nil }
        let median = starts[starts.count / 2]
        if median < 0.35 { return "left" }
        if median > 0.65 { return "right" }
        return nil
    }

    nonisolated static func hasEnoughMovement(_ strokes: [[CGPoint]]) -> Bool {
        strokes.filter { stroke in
            guard let first = stroke.first else { return false }
            return stroke.contains { hypot($0.x - first.x, $0.y - first.y) >= 50 }
        }.count >= 2
    }

    nonisolated static func recommend(strokes: [[CGPoint]], size: CGSize, hand: String) -> ReachProfile? {
        guard size.width >= 200, size.height >= 280, hasEnoughMovement(strokes) else { return nil }
        let step = 3.0
        let coreRadius = 9
        var traced = Set<Cell>()
        // A small touch corridor around each recorded segment; never connect different strokes.
        for stroke in strokes {
            for index in stroke.indices {
                let start = index == 0 ? stroke[index] : stroke[index - 1]
                let end = stroke[index]
                let length = hypot(end.x - start.x, end.y - start.y)
                guard length.isFinite, length < max(size.width, size.height) * 2 else { continue }
                let count = max(1, Int(ceil(length / 4)))
                for sample in 0...count {
                    let t = Double(sample) / Double(count)
                    let point = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
                    guard point.x.isFinite, point.y.isFinite, point.x >= 0, point.y >= 0,
                          point.x <= size.width, point.y <= size.height else { continue }
                    let cx = Int(point.x / step), cy = Int(point.y / step)
                    for dy in -6...6 {
                        for dx in -6...6 {
                            let cell = Cell(x: cx + dx, y: cy + dy)
                            let px = (Double(cell.x) + 0.5) * step
                            let py = (Double(cell.y) + 0.5) * step
                            if px >= 9 && px <= size.width - 9 && py >= 100 && py <= size.height - 9,
                               hypot(px - point.x, py - point.y) <= 18 { traced.insert(cell) }
                        }
                    }
                }
            }
        }
        let zone = largestComponent(traced)
        // Require a complete 57 × 57 pt core for every label and touch target.
        let candidates = zone.filter { cell in
            for dy in -coreRadius...coreRadius {
                for dx in -coreRadius...coreRadius where !zone.contains(Cell(x: cell.x + dx, y: cell.y + dy)) { return false }
            }
            return true
        }.sorted { $0.y == $1.y ? $0.x < $1.x : $0.y > $1.y }
        guard let first = candidates.first else { return nil }
        var seeds = [first]
        while seeds.count < 6 {
            let remaining = candidates.filter { cell in
                seeds.allSatisfy { hypot(Double(cell.x - $0.x), Double(cell.y - $0.y)) * step >= 84 }
            }
            guard let next = remaining.max(by: { a, b in
                let da = seeds.map { hypot(Double(a.x - $0.x), Double(a.y - $0.y)) }.min() ?? 0
                let db = seeds.map { hypot(Double(b.x - $0.x), Double(b.y - $0.y)) }.min() ?? 0
                return da == db ? (a.y == b.y ? a.x < b.x : a.y < b.y) : da < db
            }) else { break }
            seeds.append(next)
        }
        guard seeds.count >= 2 else { return nil }
        seeds.sort { $0.y == $1.y ? (hand == "left" ? $0.x < $1.x : $0.x > $1.x) : $0.y > $1.y }
        var ownership = partition(zone, seeds: seeds)
        // Geodesic partitioning follows the band; verify that no partition cuts a target's core.
        while seeds.count >= 2 {
            let invalid = seeds.indices.first { index in
                let cell = seeds[index]
                for dy in -coreRadius...coreRadius {
                    for dx in -coreRadius...coreRadius where ownership[Cell(x: cell.x + dx, y: cell.y + dy)] != index { return true }
                }
                return false
            }
            guard let invalid else { break }
            seeds.remove(at: invalid)
            ownership = partition(zone, seeds: seeds)
        }
        guard seeds.count >= 2 else { return nil }
        let regions = seeds.indices.map { index in
            let cells = Set(ownership.compactMap { $0.value == index ? $0.key : nil })
            return ReachRegion(anchor: ReachVertex(x: (Double(seeds[index].x) + 0.5) * step / size.width,
                                                   y: (Double(seeds[index].y) + 0.5) * step / size.height),
                               contours: contours(cells, step: step, size: size))
        }
        return ReachProfile(hand: hand, landscape: size.width > size.height, centerX: 0.5, centerY: 0.5,
                            compact: true, coverage: 1, regions: regions,
                            referenceWidth: size.width, referenceHeight: size.height)
    }

    nonisolated private static func largestComponent(_ cells: Set<Cell>) -> Set<Cell> {
        var remaining = cells
        var largest = Set<Cell>()
        while let start = remaining.min(by: { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }) {
            var queue = [start], cursor = 0
            remaining.remove(start)
            while cursor < queue.count {
                let cell = queue[cursor]; cursor += 1
                for next in cell.neighbors where remaining.remove(next) != nil { queue.append(next) }
            }
            if queue.count > largest.count { largest = Set(queue) }
        }
        return largest
    }

    nonisolated private static func partition(_ cells: Set<Cell>, seeds: [Cell]) -> [Cell: Int] {
        var owner: [Cell: Int] = [:]
        var queue: [Cell] = []
        for (index, seed) in seeds.enumerated() { owner[seed] = index; queue.append(seed) }
        var cursor = 0
        while cursor < queue.count {
            let cell = queue[cursor]; cursor += 1
            for next in cell.neighbors where cells.contains(next) && owner[next] == nil {
                owner[next] = owner[cell]
                queue.append(next)
            }
        }
        return owner
    }

    nonisolated private static func contours(_ cells: Set<Cell>, step: Double, size: CGSize) -> [[ReachVertex]] {
        var edges: [Cell: [Cell]] = [:]
        func add(_ start: Cell, _ end: Cell) { edges[start, default: []].append(end) }
        for cell in cells {
            let x = cell.x, y = cell.y
            if !cells.contains(Cell(x: x, y: y - 1)) { add(Cell(x: x, y: y), Cell(x: x + 1, y: y)) }
            if !cells.contains(Cell(x: x + 1, y: y)) { add(Cell(x: x + 1, y: y), Cell(x: x + 1, y: y + 1)) }
            if !cells.contains(Cell(x: x, y: y + 1)) { add(Cell(x: x + 1, y: y + 1), Cell(x: x, y: y + 1)) }
            if !cells.contains(Cell(x: x - 1, y: y)) { add(Cell(x: x, y: y + 1), Cell(x: x, y: y)) }
        }
        var result: [[ReachVertex]] = []
        while let start = edges.keys.min(by: { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }) {
            var loop = [start], point = start
            repeat {
                guard var choices = edges[point], let next = choices.popLast() else { break }
                if choices.isEmpty { edges.removeValue(forKey: point) } else { edges[point] = choices }
                point = next
                loop.append(point)
            } while point != start && loop.count < 20000
            if loop.count >= 4 && point == start {
                let simplified = loop.dropLast().indices.filter { index in
                    let count = loop.count - 1
                    let before = loop[(index + count - 1) % count], current = loop[index], after = loop[(index + 1) % count]
                    return (current.x - before.x) * (after.y - current.y) != (current.y - before.y) * (after.x - current.x)
                }.map { loop[$0] }
                result.append(simplified.map { ReachVertex(x: Double($0.x) * step / size.width, y: Double($0.y) * step / size.height) })
            }
        }
        return result
    }
}
