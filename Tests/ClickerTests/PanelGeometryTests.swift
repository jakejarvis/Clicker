import Foundation
import Testing

@testable import Clicker

@Suite struct PanelGeometryTests {
    let visible = NSRect(x: 0, y: 0, width: 1440, height: 875)

    @Test func centersUnderTheStatusItem() {
        let button = NSRect(x: 700, y: 876, width: 30, height: 22)
        let topLeft = PanelGeometry.topLeft(below: button, width: 264, visibleFrame: visible)
        #expect(topLeft.x == (715 - 132).rounded())
        #expect(topLeft.y == 876 - PanelGeometry.topGap)
    }

    @Test func staysInsideTheScreen() {
        let button = NSRect(x: 1420, y: 876, width: 30, height: 22)
        let topLeft = PanelGeometry.topLeft(below: button, width: 264, visibleFrame: visible)
        #expect(topLeft.x == 1440 - 264 - PanelGeometry.screenMargin)
    }

    @Test func clampsHeightToAvailableRoom() {
        let topLeft = NSPoint(x: 0, y: 300)
        let maximum = PanelGeometry.maximumHeight(topLeft: topLeft, visibleFrame: visible)
        #expect(maximum == 300 - PanelGeometry.screenMargin)
        #expect(PanelGeometry.clampedHeight(1000, maximum: maximum) == maximum)
        #expect(PanelGeometry.clampedHeight(10, maximum: maximum) == PanelGeometry.minimumHeight)
    }

    @Test func framesGrowDownwardOnWholePoints() {
        let frame = PanelGeometry.frame(topLeft: NSPoint(x: 10, y: 500.7), width: 264, height: 400.4)
        #expect(frame.maxY == 500)
        #expect(frame.height == 400)
        #expect(frame.minY == 100)
    }
}
