import SwiftUI

/// Pure geometry of the segmented clickpad: four annular sectors around a
/// round Select button. Kept free of views so the math is unit tested.
///
/// Coordinates are SwiftUI's (y grows downward); angles grow clockwise on
/// screen. The straight edges of each sector are offset from the diagonals by
/// half the gap, so the channel between neighbours has the same width at the
/// rim as it does next to the center.
enum ClickpadGeometry {
    static let diameter: CGFloat = 192
    static let selectDiameter: CGFloat = 84
    /// Channel between neighbouring sectors, and between sectors and Select.
    static let gap: CGFloat = 6
    static let cornerRadius: CGFloat = 6

    static var outerRadius: CGFloat { diameter / 2 }
    static var innerRadius: CGFloat { selectDiameter / 2 + gap }
    /// Where the arrow glyph sits: the middle of the band.
    static var arrowRadius: CGFloat { (innerRadius + outerRadius) / 2 }

    enum Direction: CaseIterable, Hashable, Sendable {
        case up
        case right
        case down
        case left

        /// Angle of the sector's center line, in radians.
        var centerAngle: CGFloat {
            switch self {
            case .right: return 0
            case .down: return .pi / 2
            case .left: return .pi
            case .up: return 3 * .pi / 2
            }
        }

        /// Unit vector pointing from the pad center through the sector.
        var unit: CGPoint {
            CGPoint(x: cos(centerAngle), y: sin(centerAngle))
        }
    }

    /// One sector with the default dimensions, optionally inset (for hairline
    /// strokes on the material fallback).
    static func path(for direction: Direction, center: CGPoint, inset: CGFloat = 0) -> Path {
        path(
            for: direction, center: center,
            outerRadius: outerRadius - inset, innerRadius: innerRadius + inset,
            gap: gap + 2 * inset, cornerRadius: max(cornerRadius - inset, 0))
    }

    /// One sector with explicit dimensions.
    static func path(
        for direction: Direction, center: CGPoint, outerRadius: CGFloat, innerRadius: CGFloat, gap: CGFloat,
        cornerRadius: CGFloat
    ) -> Path {
        guard cornerRadius > 0 else {
            return sharpPath(
                for: direction, center: center, outerRadius: outerRadius, innerRadius: innerRadius, gap: gap)
        }
        // Inset the sector by the corner radius, then grow it back with a
        // round-joined stroke: every corner comes out rounded and every edge
        // lands back where it started.
        let core = sharpPath(
            for: direction, center: center, outerRadius: outerRadius - cornerRadius,
            innerRadius: innerRadius + cornerRadius, gap: gap + 2 * cornerRadius)
        let rim = core.strokedPath(StrokeStyle(lineWidth: 2 * cornerRadius, lineCap: .round, lineJoin: .round))
        return core.union(rim)
    }

    /// Bounding box of a sector drawn around the origin, with default dimensions.
    static func bounds(for direction: Direction) -> CGRect {
        boundsByDirection[direction] ?? .zero
    }

    private static let boundsByDirection: [Direction: CGRect] = Dictionary(
        uniqueKeysWithValues: Direction.allCases.map { ($0, path(for: $0, center: .zero).boundingRect) })

    /// Angle by which a sector edge moves in from the diagonal at a given
    /// radius so the straight edge sits `gap / 2` from the diagonal.
    static func edgeInset(atRadius radius: CGFloat, gap: CGFloat) -> CGFloat {
        asin(min(gap / (2 * radius), 1))
    }

    private static func sharpPath(
        for direction: Direction, center: CGPoint, outerRadius: CGFloat, innerRadius: CGFloat, gap: CGFloat
    ) -> Path {
        let outerInset = edgeInset(atRadius: outerRadius, gap: gap)
        let innerInset = edgeInset(atRadius: innerRadius, gap: gap)
        let start = direction.centerAngle - .pi / 4
        let end = direction.centerAngle + .pi / 4

        var path = Path()
        path.addArc(
            center: center, radius: outerRadius,
            startAngle: .radians(start + outerInset), endAngle: .radians(end - outerInset), clockwise: false)
        path.addArc(
            center: center, radius: innerRadius,
            startAngle: .radians(end - innerInset), endAngle: .radians(start + innerInset), clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// A clickpad sector as a SwiftUI shape. The shape is drawn in the sector's
/// own bounding box (see `ClickpadGeometry.bounds(for:)`), so each direction
/// button is only as large as the sector it draws.
struct ClickpadSegment: InsettableShape {
    let direction: ClickpadGeometry.Direction
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let bounds = ClickpadGeometry.bounds(for: direction)
        let center = CGPoint(x: rect.minX - bounds.minX, y: rect.minY - bounds.minY)
        return ClickpadGeometry.path(for: direction, center: center, inset: insetAmount)
    }

    func inset(by amount: CGFloat) -> ClickpadSegment {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
