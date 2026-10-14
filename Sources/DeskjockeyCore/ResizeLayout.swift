import Foundation

// MARK: - Resize layout

/// Works out where displays go after the user changes a display's resolution.
///
/// macOS moves a display to a spot of its own choosing when its size changes.
/// These functions compute origins that keep the arrangement the user had.
/// Coordinates are in points, with y growing downward, as in CGDisplayBounds.
public enum ResizeLayout {

    /// Returns target origins for the live displays, keyed by runtime ID.
    ///
    /// Uses `savedLayout` when one matches the new sizes. Otherwise keeps each
    /// resized display on the same side of the same neighbor as in `pairs`' slots.
    /// The display at (0, 0) stays there, because macOS requires the main display
    /// at the origin.
    public static func targetOrigins(
        pairs: [(display: DisplaySnapshot, slot: MonitorSlotProfile)],
        savedLayout: [MonitorSlotProfile]?
    ) -> [String: DisplayPoint] {
        var targets: [String: DisplayFrame] = [:]

        if let savedLayout {
            for pair in pairs {
                let saved = savedLayout.first {
                    $0.modelName == pair.slot.modelName && $0.slotIndex == pair.slot.slotIndex
                }
                targets[pair.display.runtimeID] = saved?.targetFrame ?? pair.display.frame
            }
        } else {
            for pair in pairs {
                let oldFrame = pair.slot.targetFrame
                let newSize = pair.display.frame.size
                if oldFrame.size == newSize {
                    targets[pair.display.runtimeID] = oldFrame
                    continue
                }
                let others = pairs
                    .filter { $0.display.runtimeID != pair.display.runtimeID }
                    .map { $0.slot.targetFrame }
                let origin = anchoredOrigin(of: oldFrame, newSize: newSize, neighbors: others)
                targets[pair.display.runtimeID] = DisplayFrame(origin: origin, size: newSize)
            }
        }

        let main = pairs.first { $0.display.frame.origin == DisplayPoint(x: 0, y: 0) }
        let shift = main.flatMap { targets[$0.display.runtimeID]?.origin } ?? DisplayPoint(x: 0, y: 0)
        return targets.mapValues {
            DisplayPoint(x: $0.origin.x - shift.x, y: $0.origin.y - shift.y)
        }
    }

    /// Returns the new origin for a display that changed from `oldFrame` to `newSize`.
    ///
    /// Keeps the display on the same side of the neighbor it shared the longest edge with.
    /// Along that edge, flush edges stay flush; otherwise the center offset scales with the size.
    /// Returns the old origin if the display touched no neighbor.
    static func anchoredOrigin(
        of oldFrame: DisplayFrame,
        newSize: DisplaySize,
        neighbors: [DisplayFrame]
    ) -> DisplayPoint {
        let touching = neighbors.compactMap { neighbor in
            side(of: oldFrame, relativeTo: neighbor).map { (neighbor: neighbor, side: $0.side, overlap: $0.overlap) }
        }
        guard let anchor = touching.max(by: { $0.overlap < $1.overlap }) else {
            return oldFrame.origin
        }
        let n = anchor.neighbor

        switch anchor.side {
        case .above, .below:
            let x = alignedStart(
                oldStart: oldFrame.origin.x, oldLength: oldFrame.size.width, newLength: newSize.width,
                neighborStart: n.origin.x, neighborLength: n.size.width
            )
            let y = anchor.side == .above ? n.origin.y - newSize.height : n.origin.y + n.size.height
            return DisplayPoint(x: x, y: y)
        case .left, .right:
            let y = alignedStart(
                oldStart: oldFrame.origin.y, oldLength: oldFrame.size.height, newLength: newSize.height,
                neighborStart: n.origin.y, neighborLength: n.size.height
            )
            let x = anchor.side == .left ? n.origin.x - newSize.width : n.origin.x + n.size.width
            return DisplayPoint(x: x, y: y)
        }
    }

    enum Side {
        case above, below, left, right
    }

    /// Returns which side of `neighbor` the `frame` sits on, and the length of the shared edge.
    static func side(of frame: DisplayFrame, relativeTo neighbor: DisplayFrame) -> (side: Side, overlap: Int)? {
        let horizontalOverlap = min(frame.origin.x + frame.size.width, neighbor.origin.x + neighbor.size.width)
            - max(frame.origin.x, neighbor.origin.x)
        let verticalOverlap = min(frame.origin.y + frame.size.height, neighbor.origin.y + neighbor.size.height)
            - max(frame.origin.y, neighbor.origin.y)

        if horizontalOverlap > 0 {
            if frame.origin.y + frame.size.height == neighbor.origin.y { return (.above, horizontalOverlap) }
            if frame.origin.y == neighbor.origin.y + neighbor.size.height { return (.below, horizontalOverlap) }
        }
        if verticalOverlap > 0 {
            if frame.origin.x + frame.size.width == neighbor.origin.x { return (.left, verticalOverlap) }
            if frame.origin.x == neighbor.origin.x + neighbor.size.width { return (.right, verticalOverlap) }
        }
        return nil
    }

    /// Returns the new start of a display along the edge it shares with its neighbor.
    static func alignedStart(
        oldStart: Int,
        oldLength: Int,
        newLength: Int,
        neighborStart: Int,
        neighborLength: Int
    ) -> Int {
        if oldStart == neighborStart {
            return neighborStart
        }
        if oldStart + oldLength == neighborStart + neighborLength {
            return neighborStart + neighborLength - newLength
        }
        let oldCenterOffset = Double(oldStart) + Double(oldLength) / 2
            - (Double(neighborStart) + Double(neighborLength) / 2)
        let newCenterOffset = oldCenterOffset * Double(newLength) / Double(oldLength)
        let newCenter = Double(neighborStart) + Double(neighborLength) / 2 + newCenterOffset
        return Int((newCenter - Double(newLength) / 2).rounded())
    }
}
