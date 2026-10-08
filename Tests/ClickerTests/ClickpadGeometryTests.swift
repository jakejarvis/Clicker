import SwiftUI
import Testing

@testable import Clicker

@Suite struct ClickpadGeometryTests {
    typealias Direction = ClickpadGeometry.Direction

    private let origin = CGPoint.zero
    private let halfGap = ClickpadGeometry.gap / 2

    private func sector(_ direction: Direction, cornerRadius: CGFloat = ClickpadGeometry.cornerRadius) -> Path {
        ClickpadGeometry.path(
            for: direction, center: origin, outerRadius: ClickpadGeometry.outerRadius,
            innerRadius: ClickpadGeometry.innerRadius, gap: ClickpadGeometry.gap, cornerRadius: cornerRadius)
    }

    private func point(radius: CGFloat, angle: CGFloat) -> CGPoint {
        CGPoint(x: radius * cos(angle), y: radius * sin(angle))
    }

    @Test func sectorsCoverTheirCenterLines() {
        for direction in Direction.allCases {
            let inside = point(radius: ClickpadGeometry.arrowRadius, angle: direction.centerAngle)
            #expect(sector(direction).contains(inside), "\(direction) should contain its arrow position")
            for other in Direction.allCases where other != direction {
                #expect(!sector(other).contains(inside), "\(other) should not contain \(direction)'s arrow")
            }
        }
    }

    @Test func gapsHaveConstantWidth() {
        // Walk the diagonal between Up and Right at several radii. Half a gap
        // plus one point to either side is inside a sector; half a gap minus
        // one point is still in the channel.
        let diagonal = -CGFloat.pi / 4
        let up = sector(.up, cornerRadius: 0)
        let right = sector(.right, cornerRadius: 0)
        // Perpendicular to the diagonal, toward Right (increasing angle).
        let towardRight = CGPoint(x: -sin(diagonal), y: cos(diagonal))
        for radius: CGFloat in [52, 60, 72, 84, 92] {
            let onDiagonal = point(radius: radius, angle: diagonal)
            func shifted(_ distance: CGFloat) -> CGPoint {
                CGPoint(x: onDiagonal.x + towardRight.x * distance, y: onDiagonal.y + towardRight.y * distance)
            }
            #expect(!up.contains(onDiagonal) && !right.contains(onDiagonal), "r=\(radius)")
            #expect(right.contains(shifted(halfGap + 1)), "r=\(radius)")
            #expect(up.contains(shifted(-(halfGap + 1))), "r=\(radius)")
            #expect(!right.contains(shifted(halfGap - 1)), "r=\(radius)")
            #expect(!up.contains(shifted(-(halfGap - 1))), "r=\(radius)")
        }
    }

    @Test func sectorsDoNotOverlapAndLeaveRoomForSelect() {
        let paths = Direction.allCases.map { sector($0) }
        var hits = 0
        for x in stride(from: -96, through: 96, by: 4) {
            for y in stride(from: -96, through: 96, by: 4) {
                let p = CGPoint(x: x, y: y)
                let count = paths.filter { $0.contains(p) }.count
                #expect(count <= 1, "point \(p) is in \(count) sectors")
                hits += count
                let radius = hypot(p.x, p.y)
                if radius < ClickpadGeometry.innerRadius {
                    #expect(count == 0, "point \(p) inside the Select ring should be empty")
                }
                if radius > ClickpadGeometry.outerRadius {
                    #expect(count == 0, "point \(p) outside the rim should be empty")
                }
            }
        }
        #expect(hits > 0)
    }

    @Test func sectorsAreRotationsOfEachOther() {
        // Sample points at least a few points away from every edge and
        // rounded corner: `Path.contains` differs between toolchains on the
        // boundary itself, which made this flaky in CI at r=50, ±0.7 rad.
        let up = sector(.up)
        let right = sector(.right)
        for radius: CGFloat in [56, 72, 90] {
            for step in stride(from: -0.6, through: 0.6, by: 0.1) {
                let angle = CGFloat(step)
                let inUp = up.contains(point(radius: radius, angle: Direction.up.centerAngle + angle))
                let inRight = right.contains(point(radius: radius, angle: Direction.right.centerAngle + angle))
                #expect(inUp == inRight, "r=\(radius) offset=\(step)")
            }
        }
    }

    @Test func boundsMirrorAcrossTheCenter() {
        let up = ClickpadGeometry.bounds(for: .up)
        let down = ClickpadGeometry.bounds(for: .down)
        #expect(abs(up.minY + down.maxY) < 0.01)
        #expect(abs(up.width - down.width) < 0.01)
        #expect(up.maxY < 0 && down.minY > 0)
        #expect(abs(up.minY + ClickpadGeometry.outerRadius) < 0.01)
    }

    @Test func insetSectorStaysInsideTheOriginal() {
        let full = sector(.left)
        let inset = ClickpadGeometry.path(for: .left, center: origin, inset: 2)
        for x in stride(from: -96, through: 0, by: 3) {
            for y in stride(from: -70, through: 70, by: 3) {
                let p = CGPoint(x: x, y: y)
                if inset.contains(p) {
                    #expect(full.contains(p), "inset point \(p) escaped the original")
                }
            }
        }
    }

    @Test func segmentShapeDrawsInsideItsFrame() {
        let bounds = ClickpadGeometry.bounds(for: .right)
        let frame = CGRect(origin: CGPoint(x: 10, y: 20), size: bounds.size)
        let drawn = ClickpadSegment(direction: .right).path(in: frame).boundingRect
        #expect(abs(drawn.minX - frame.minX) < 0.01)
        #expect(abs(drawn.minY - frame.minY) < 0.01)
        #expect(abs(drawn.maxX - frame.maxX) < 0.01)
        #expect(abs(drawn.maxY - frame.maxY) < 0.01)
    }
}
