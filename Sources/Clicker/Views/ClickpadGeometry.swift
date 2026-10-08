import SwiftUI

/// Pure geometry of the clickpad: a ring of four quadrants around a round
/// Select. Kept free of views so the math is unit tested.
///
/// Coordinates are SwiftUI's (y grows downward); angles grow clockwise on
/// screen.
enum ClickpadGeometry {
    static let diameter: CGFloat = 192
    static let selectDiameter: CGFloat = 84
    /// Channel between the ring and Select.
    static let gap: CGFloat = 3

    static var outerRadius: CGFloat { diameter / 2 }
    static var innerRadius: CGFloat { selectDiameter / 2 + gap }
    /// Where the arrow glyph sits: the middle of the band.
    static var arrowRadius: CGFloat { (innerRadius + outerRadius) / 2 }

    enum Direction: CaseIterable, Hashable, Sendable {
        case up
        case right
        case down
        case left

        /// Angle of the quadrant's center line, in radians.
        var centerAngle: CGFloat {
            switch self {
            case .right: return 0
            case .down: return .pi / 2
            case .left: return .pi
            case .up: return 3 * .pi / 2
            }
        }

        /// Unit vector pointing from the pad center through the quadrant.
        var unit: CGPoint {
            CGPoint(x: cos(centerAngle), y: sin(centerAngle))
        }
    }

    /// The quadrant under a point, or nil outside the band. Each direction
    /// owns the 90° arc centered on its axis, split along the diagonals.
    static func direction(at point: CGPoint, center: CGPoint) -> Direction? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let radius = (dx * dx + dy * dy).squareRoot()
        guard radius >= innerRadius, radius <= outerRadius else { return nil }
        if abs(dx) > abs(dy) {
            return dx > 0 ? .right : .left
        }
        return dy > 0 ? .down : .up
    }

    /// One quadrant of the band, diagonal to diagonal.
    static func quadrantPath(for direction: Direction, center: CGPoint) -> Path {
        let start = direction.centerAngle - .pi / 4
        let end = direction.centerAngle + .pi / 4
        var path = Path()
        path.addArc(
            center: center, radius: outerRadius, startAngle: .radians(start), endAngle: .radians(end),
            clockwise: false)
        path.addArc(
            center: center, radius: innerRadius, startAngle: .radians(end), endAngle: .radians(start), clockwise: true
        )
        path.closeSubpath()
        return path
    }
}

/// The band as one shape: the disc with Select's hole cut out, so one glass
/// surface backs all four directions without stacking on the glass Select.
struct ClickpadRing: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = ClickpadGeometry.outerRadius - insetAmount
        let inner = ClickpadGeometry.innerRadius + insetAmount
        let disc = Path(
            ellipseIn: CGRect(x: center.x - outer, y: center.y - outer, width: 2 * outer, height: 2 * outer))
        let hole = Path(
            ellipseIn: CGRect(x: center.x - inner, y: center.y - inner, width: 2 * inner, height: 2 * inner))
        return disc.subtracting(hole)
    }

    func inset(by amount: CGFloat) -> ClickpadRing {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

/// One quadrant of the band, drawn around the center of its frame. Used for
/// the hover and press wash over the ring.
struct ClickpadQuadrant: Shape {
    let direction: ClickpadGeometry.Direction

    func path(in rect: CGRect) -> Path {
        ClickpadGeometry.quadrantPath(for: direction, center: CGPoint(x: rect.midX, y: rect.midY))
    }
}
