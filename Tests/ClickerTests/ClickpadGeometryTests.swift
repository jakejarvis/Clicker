import SwiftUI
import Testing

@testable import Clicker

@Suite struct ClickpadGeometryTests {
    typealias Direction = ClickpadGeometry.Direction

    private let center = CGPoint(x: 100, y: 100)

    private func point(radius: CGFloat, angle: CGFloat) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }

    @Test func directionsOwnTheirArrows() {
        for direction in Direction.allCases {
            let arrow = point(radius: ClickpadGeometry.arrowRadius, angle: direction.centerAngle)
            #expect(ClickpadGeometry.direction(at: arrow, center: center) == direction)
        }
    }

    @Test func diagonalsSplitTheQuadrants() {
        let justInsideUp = point(radius: ClickpadGeometry.arrowRadius, angle: Direction.up.centerAngle + 0.75)
        let justInsideRight = point(radius: ClickpadGeometry.arrowRadius, angle: Direction.right.centerAngle - 0.75)
        #expect(ClickpadGeometry.direction(at: justInsideUp, center: center) == .up)
        #expect(ClickpadGeometry.direction(at: justInsideRight, center: center) == .right)
    }

    @Test func nothingOutsideTheBand() {
        #expect(ClickpadGeometry.direction(at: center, center: center) == nil)
        let inSelect = point(radius: ClickpadGeometry.selectDiameter / 2 - 1, angle: 0)
        let inChannel = point(radius: ClickpadGeometry.innerRadius - 1, angle: 1)
        let pastRim = point(radius: ClickpadGeometry.outerRadius + 1, angle: 2)
        #expect(ClickpadGeometry.direction(at: inSelect, center: center) == nil)
        #expect(ClickpadGeometry.direction(at: inChannel, center: center) == nil)
        #expect(ClickpadGeometry.direction(at: pastRim, center: center) == nil)
    }

    @Test func quadrantPathsMatchTheHitTest() {
        // Walk the band and check the drawn quadrant agrees with direction(at:).
        for direction in Direction.allCases {
            let path = ClickpadGeometry.quadrantPath(for: direction, center: center)
            for radius in stride(from: ClickpadGeometry.innerRadius + 1, to: ClickpadGeometry.outerRadius, by: 8) {
                for step in 0..<36 {
                    let angle = CGFloat(step) * .pi / 18 + 0.01
                    let p = point(radius: radius, angle: angle)
                    let hit = ClickpadGeometry.direction(at: p, center: center) == direction
                    #expect(path.contains(p) == hit, "\(direction) r=\(radius) angle=\(angle)")
                }
            }
        }
    }

    @Test func ringHasAHole() {
        let rect = CGRect(x: 0, y: 0, width: ClickpadGeometry.diameter, height: ClickpadGeometry.diameter)
        let ring = ClickpadRing().path(in: rect)
        let mid = CGPoint(x: rect.midX, y: rect.midY)
        #expect(!ring.contains(mid, eoFill: true))
        // Off the horizontal axis: both circles start their subpaths at y = mid.y, and CoreGraphics on
        // macOS 26 (the CI runner) miscounts crossings for a point level with those vertices.
        let offset = ClickpadGeometry.arrowRadius / 2.squareRoot()
        #expect(ring.contains(CGPoint(x: mid.x + offset, y: mid.y + offset), eoFill: true))
        #expect(!ring.contains(CGPoint(x: rect.maxX - 1, y: rect.maxY - 1), eoFill: true))
    }
}
