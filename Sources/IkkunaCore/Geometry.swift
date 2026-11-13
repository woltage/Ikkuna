import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum Direction: String, CaseIterable, Codable, Hashable {
    case left, right, up, down
    public var opposite: Direction {
        switch self { case .left: return .right; case .right: return .left; case .up: return .down; case .down: return .up }
    }
    public func distances(from a: CGRect, to b: CGRect) -> (primary: CGFloat, cross: CGFloat) {
        let dx = b.midX - a.midX, dy = b.midY - a.midY
        switch self {
        case .left: return (-dx, abs(dy))
        case .right: return (dx, abs(dy))
        case .up: return (-dy, abs(dx))
        case .down: return (dy, abs(dx))
        }
    }
}

public struct WindowRect: Equatable {
    public let id: UInt32
    public var frame: CGRect
    public init(_ id: UInt32, _ frame: CGRect) { self.id = id; self.frame = frame }
}

public enum Geometry {
    public static func approximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.minX-b.minX) < tolerance && abs(a.minY-b.minY) < tolerance &&
        abs(a.width-b.width) < tolerance && abs(a.height-b.height) < tolerance
    }

    /// Repeated center commands alternate between half and three-quarter width.
    public static func centerCycle(from frame: CGRect, in screen: CGRect, centeredOn midX: CGFloat, gap: CGFloat) -> CGRect {
        func centered(_ fraction: CGFloat) -> CGRect {
            let width = max(1, (screen.width-2*gap)*fraction)
            return CGRect(x: midX-width/2, y: screen.minY+gap,
                          width: width, height: max(1, screen.height-2*gap))
        }
        let narrow = centered(0.5)
        return approximatelyEqual(frame, narrow) ? centered(0.75) : narrow
    }

    public static func tile(in screen: CGRect, columns: Int, rows: Int, column: Int, row: Int, gap: CGFloat) -> CGRect {
        let g = min(max(0, gap), min(screen.width / CGFloat(columns + 1), screen.height / CGFloat(rows + 1)) / 2)
        let w = (screen.width - g * CGFloat(columns + 1)) / CGFloat(columns)
        let h = (screen.height - g * CGFloat(rows + 1)) / CGFloat(rows)
        return CGRect(x: screen.minX + g + CGFloat(column) * (w + g),
                      y: screen.minY + g + CGFloat(row) * (h + g), width: w, height: h)
    }

    public static func screenIndex(for rect: CGRect, screens: [CGRect]) -> Int? {
        screens.indices.max { area(rect.intersection(screens[$0])) < area(rect.intersection(screens[$1])) }
    }

    public static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull || rect.isEmpty ? 0 : rect.width * rect.height
    }

    /// Exact union coverage: overlapping occluders must not be counted twice.
    public static func coveredFraction(of frame: CGRect, by occluders: [CGRect]) -> CGFloat {
        let clips = occluders.map { $0.intersection(frame) }.filter { area($0) > 0 }
        let xs = Array(Set(clips.flatMap { [$0.minX, $0.maxX] })).sorted()
        guard xs.count > 1, area(frame) > 0 else { return 0 }
        var covered: CGFloat = 0
        for i in 0..<(xs.count - 1) {
            let intervals = clips.filter { $0.minX < xs[i+1] && $0.maxX > xs[i] }.sorted { $0.minY < $1.minY }
            var end = -CGFloat.greatestFiniteMagnitude, height: CGFloat = 0
            for clip in intervals {
                let start = max(clip.minY, end)
                height += max(0, clip.maxY-start)
                end = max(end, clip.maxY)
            }
            covered += (xs[i+1]-xs[i]) * height
        }
        return min(1, covered / area(frame))
    }

    public static func directionalTarget(from current: WindowRect, candidates: [WindowRect], direction: Direction,
                                         remembered: UInt32? = nil) -> UInt32? {
        let others = candidates.filter { $0.id != current.id }
        if let remembered, let target = others.first(where: { $0.id == remembered }) {
            let d = direction.distances(from: current.frame, to: target.frame)
            if d.primary > 1 && d.cross <= d.primary { return target.id }
        }
        let forward = others.filter { direction.distances(from: current.frame, to: $0.frame).primary > 1 }
        if let best = forward.min(by: {
            let a = direction.distances(from: current.frame, to: $0.frame)
            let b = direction.distances(from: current.frame, to: $1.frame)
            return a.primary + 2*a.cross < b.primary + 2*b.cross
        }) { return best.id }
        return others.filter { direction.distances(from: current.frame, to: $0.frame).primary < -1 }.min {
            let a = direction.distances(from: current.frame, to: $0.frame)
            let b = direction.distances(from: current.frame, to: $1.frame)
            return a.primary == b.primary ? a.cross < b.cross : a.primary < b.primary
        }?.id
    }

    public static func moved(_ frame: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return frame }
        return CGRect(x: target.minX + (frame.minX-source.minX)/source.width * target.width,
                      y: target.minY + (frame.minY-source.minY)/source.height * target.height,
                      width: min(target.width, frame.width/source.width * target.width),
                      height: min(target.height, frame.height/source.height * target.height))
    }

    public static func fill(_ frame: CGRect, in screen: CGRect, neighbors: [CGRect], left: Bool,
                            row: Int? = nil, gap: CGFloat) -> CGRect {
        let band = tile(in: screen, columns: 1, rows: row == nil ? 1 : 2, column: 0, row: row ?? 0, gap: gap)
        let blockers = neighbors.filter { $0.maxY > band.minY + 1 && $0.minY < band.maxY - 1 }
        var start = band.minX, end = band.maxX
        if left {
            for neighbor in blockers where neighbor.minX <= band.minX + 20 {
                start = max(start, neighbor.maxX + gap)
            }
            for neighbor in blockers where neighbor.minX > start {
                end = min(end, neighbor.minX - gap)
            }
        } else {
            for neighbor in blockers where neighbor.maxX >= band.maxX - 20 {
                end = min(end, neighbor.minX - gap)
            }
            for neighbor in blockers where neighbor.maxX < end {
                start = max(start, neighbor.maxX + gap)
            }
        }
        guard end > start else { return frame }
        return CGRect(x: start, y: band.minY, width: end-start, height: band.height)
    }

}

/// A press holds a fixed participant set. Only the shared column boundary moves.
public struct ResizePlan {
    public let originals: [UInt32: CGRect]
    public let primary: Set<UInt32>
    public let neighbors: Set<UInt32>
    public let towardRight: Bool
    public let minimumWidth: CGFloat
    private let vertical: Bool
    private static func transpose(_ f: CGRect) -> CGRect {
        CGRect(x: f.minY, y: f.minX, width: f.height, height: f.width)
    }
    private let lower: CGFloat
    private let upper: CGFloat

    public init(focused: WindowRect, windows: [WindowRect], screen: CGRect, minimumWidth: CGFloat = 200, vertical: Bool = false) {
        self.vertical = vertical
        let focused = vertical ? WindowRect(focused.id, Self.transpose(focused.frame)) : focused
        let windows = vertical ? windows.map { WindowRect($0.id, Self.transpose($0.frame)) } : windows
        let screen = vertical ? Self.transpose(screen) : screen
        self.minimumWidth = minimumWidth
        let f = focused.frame
        let aligned = windows.filter { abs($0.frame.minX-f.minX) < 20 && abs($0.frame.maxX-f.maxX) < 20 }
        var own = Dictionary(uniqueKeysWithValues: aligned.map { ($0.id, $0.frame) })
        own[focused.id] = f
        let right = windows.filter { window in own[window.id] == nil && abs(window.frame.minX-f.maxX) <= 24 && own.values.contains { window.frame.maxY > $0.minY && window.frame.minY < $0.maxY } }
        let left = windows.filter { window in own[window.id] == nil && abs(window.frame.maxX-f.minX) <= 24 && own.values.contains { window.frame.maxY > $0.minY && window.frame.minY < $0.maxY } }
        let useRight = !right.isEmpty || (left.isEmpty && screen.maxX-f.maxX >= f.minX-screen.minX)
        towardRight = useRight
        let others = useRight ? right : left
        primary = Set(own.keys)
        neighbors = Set(others.map(\.id))
        var all = own
        for w in others { all[w.id] = w.frame }
        originals = vertical ? all.mapValues { Self.transpose($0) } : all
        // Signed delta means growth of the focused column, regardless of side.
        lower = own.values.map { min(0, minimumWidth-$0.width) }.max() ?? 0
        if others.isEmpty {
            upper = max(0, useRight ? screen.maxX-f.maxX : f.minX-screen.minX)
        } else {
            upper = max(0, others.map { $0.frame.width-minimumWidth }.min() ?? 0)
        }
    }

    public func frames(delta: CGFloat) -> [UInt32: CGRect] {
        let d = min(upper, max(lower, delta))
        return originals.reduce(into: [UInt32: CGRect]()) { result, item in
            var f = vertical ? Self.transpose(item.value) : item.value
            if primary.contains(item.key) {
                f.size.width += d
                if !towardRight { f.origin.x -= d }
            } else {
                f.size.width -= d
                if towardRight { f.origin.x += d }
            }
            result[item.key] = vertical ? Self.transpose(f) : f
        }
    }
}
