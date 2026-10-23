// Draws the release DMG's window background into Resources/DMG/background.tiff
// (1x and 2x in one HiDPI TIFF, which Finder picks between). Previews land in
// dist/dmg/. Run after changing the artwork or the layout:
//   swift script/render_dmg_background.swift
//
// Clicker and Applications are two apps on the Apple TV home screen, and
// between them the remote's clickpad presses right, moving the focus to
// Applications. Finder draws icon labels in black on any background picture,
// even in Dark Mode, so the labels fall on pure black under the tiles, where
// they vanish. Positions are in points from the top left and must match the
// icon locations in script/make_dmg_layout.py.
import AppKit

// 320 pt show under a 32 pt title bar (macOS 26 and later); the extra 20 pt
// cover the shorter title bar on macOS 15.
let size = CGSize(width: 640, height: 340)
let iconRow = 152.0
let iconColumns = [150.0, 490.0]
// A tvOS app tile is 5:3. Finder's labels start about 58 pt below the center
// of a 96 pt icon, so the tile ends above them.
let tileSize = CGSize(width: 180, height: 108)
let tileRadius = 16.0
let padCenter = CGPoint(x: 320, y: iconRow)
// The app's ClickpadGeometry (192 pt pad, 84 pt Select, 3 pt channel) at 92 pt.
let padDiameter = 92.0
let padScale = padDiameter / 192
let outerRadius = padDiameter / 2
let innerRadius = (84 / 2 + 3) * padScale
let selectRadius = 84 / 2 * padScale
let arrowRadius = (innerRadius + outerRadius) / 2
let captionBaseline = iconRow + 72
// The site's muted gray.
let muted = NSColor(srgbRed: 0x8f / 255, green: 0x8f / 255, blue: 0x8f / 255, alpha: 1)

let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "..").standardized
let output = directory.appending(path: "Resources/DMG/background.tiff")
let previews = directory.appending(path: "dist/dmg")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func white(_ alpha: Double) -> CGColor { CGColor(gray: 1, alpha: alpha) }

func rgb(_ hex: Int) -> CGColor {
    CGColor(
        srgbRed: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255,
        blue: Double(hex & 0xff) / 255, alpha: 1)
}

func circle(_ center: CGPoint, _ radius: Double) -> CGPath {
    CGPath(
        ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius),
        transform: nil)
}

/// The band between Select and the rim, diagonal to diagonal around `angle`.
func quadrant(around angle: Double) -> CGPath {
    let path = CGMutablePath()
    path.addArc(
        center: padCenter, radius: outerRadius, startAngle: angle - .pi / 4, endAngle: angle + .pi / 4,
        clockwise: false)
    path.addArc(
        center: padCenter, radius: innerRadius, startAngle: angle + .pi / 4, endAngle: angle - .pi / 4,
        clockwise: true)
    path.closeSubpath()
    return path
}

func tile(centerX: Double) -> CGPath {
    let rect = CGRect(
        x: centerX - tileSize.width / 2, y: iconRow - tileSize.height / 2, width: tileSize.width,
        height: tileSize.height)
    return CGPath(roundedRect: rect, cornerWidth: tileRadius, cornerHeight: tileRadius, transform: nil)
}

/// Fills `path` with a gradient running from `start` to `end`.
func fill(_ context: CGContext, _ path: CGPath, _ colors: [CGColor], from start: CGPoint, to end: CGPoint) {
    context.saveGState()
    context.addPath(path)
    context.clip(using: .evenOdd)
    let gradient = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: nil)!
    context.drawLinearGradient(gradient, start: start, end: end, options: [])
    context.restoreGState()
}

/// Fills `path` top to bottom, the way a lit surface shades.
func fillLit(_ context: CGContext, _ path: CGPath, _ colors: [CGColor]) {
    let box = path.boundingBox
    fill(context, path, colors, from: CGPoint(x: 0, y: box.minY), to: CGPoint(x: 0, y: box.maxY))
}

func dropShadow(_ context: CGContext, _ path: CGPath, blur: Double, alpha: Double) {
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: blur * 0.45), blur: blur, color: CGColor(gray: 0, alpha: alpha))
    context.addPath(path)
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fillPath()
    context.restoreGState()
}

/// A hairline just inside the edge.
func rim(_ context: CGContext, _ path: CGPath, _ color: CGColor) {
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.addPath(path)
    context.setLineWidth(1)
    context.setStrokeColor(color)
    context.strokePath()
    context.restoreGState()
}

func symbol(_ name: String, pointSize: Double, alpha: Double) -> NSImage {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(white: 1, alpha: alpha)]))
    guard
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    else { fail("no symbol \(name)") }
    return image
}

func draw(_ context: CGContext) {
    // Black, with a faint light from above that fades out before the labels.
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(origin: .zero, size: size))
    let light = CGPoint(x: size.width / 2, y: -40)
    let glow = CGGradient(colorsSpace: nil, colors: [white(0.085), white(0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: light, startRadius: 0, endCenter: light, endRadius: 240, options: [])

    // Clicker: a charcoal tile that the icon's dark squircle melts into.
    let clicker = tile(centerX: iconColumns[0])
    dropShadow(context, clicker, blur: 10, alpha: 0.6)
    fillLit(context, clicker, [rgb(0x2c2c30), rgb(0x18181b)])
    rim(context, clicker, white(0.1))

    // Applications: App Store blue, and focused, with a deep shadow and the
    // sheen a focused tile catches.
    let applications = tile(centerX: iconColumns[1])
    let box = applications.boundingBox
    dropShadow(context, applications, blur: 30, alpha: 0.9)
    fillLit(context, applications, [rgb(0x4a95ff), rgb(0x1d5fd8)])
    fill(
        context, applications, [white(0.35), white(0)], from: CGPoint(x: box.minX, y: box.minY),
        to: CGPoint(x: box.midX, y: box.maxY))
    rim(context, applications, white(0.25))

    // The ring and Select, with the channel between them left dark.
    let ring = CGMutablePath()
    ring.addPath(circle(padCenter, outerRadius))
    ring.addPath(circle(padCenter, innerRadius))
    fillLit(context, ring, [white(0.14), white(0.07)])
    fillLit(context, circle(padCenter, selectRadius), [white(0.16), white(0.08)])

    // The pressed quadrant, washed like a held button in the app.
    context.addPath(quadrant(around: 0))
    context.setFillColor(white(0.17))
    context.fillPath()

    context.setLineWidth(1)
    context.setStrokeColor(white(0.16))
    for radius in [outerRadius - 0.5, innerRadius + 0.5, selectRadius - 0.5] {
        context.addPath(circle(padCenter, radius))
    }
    context.strokePath()

    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

    // Arrows: three at rest, and the lit one pointing at Applications.
    let glyphSize = 16 * padScale * 1.25
    let arrows: [(String, Double, Double)] = [
        ("chevron.up", -.pi / 2, 0.32), ("chevron.down", .pi / 2, 0.32), ("chevron.left", .pi, 0.32),
        ("chevron.right", 0, 1),
    ]
    for (name, angle, alpha) in arrows {
        let image = symbol(name, pointSize: glyphSize, alpha: alpha)
        let center = CGPoint(x: padCenter.x + arrowRadius * cos(angle), y: padCenter.y + arrowRadius * sin(angle))
        let rect = CGRect(
            x: center.x - image.size.width / 2, y: center.y - image.size.height / 2,
            width: image.size.width, height: image.size.height)
        context.saveGState()
        if alpha == 1 { context.setShadow(offset: .zero, blur: 8, color: white(0.8)) }
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        context.restoreGState()
    }

    let font = NSFont.systemFont(ofSize: 12, weight: .medium)
    let caption = NSAttributedString(string: "Drag to install", attributes: [.font: font, .foregroundColor: muted])
    caption.draw(at: CGPoint(x: (size.width - caption.size().width) / 2, y: captionBaseline - font.ascender))
    NSGraphicsContext.current = nil
}

func render(scale: Int) -> NSBitmapImageRep {
    let pixels = (Int(size.width) * scale, Int(size.height) * scale)
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels.0, pixelsHigh: pixels.1, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let graphics = NSGraphicsContext(bitmapImageRep: rep)
    else { fail("could not allocate a \(scale)x bitmap") }
    let context = graphics.cgContext
    // Points from the top left, like Finder's icon positions.
    context.translateBy(x: 0, y: Double(pixels.1))
    context.scaleBy(x: Double(scale), y: -Double(scale))
    draw(context)
    context.flush()
    rep.size = size
    return rep
}

let reps = [render(scale: 1), render(scale: 2)]
try? FileManager.default.createDirectory(at: previews, withIntermediateDirectories: true)
for (rep, name) in zip(reps, ["background.png", "background@2x.png"]) {
    guard let png = rep.representation(using: .png, properties: [:]) else { fail("could not encode \(name)") }
    try png.write(to: previews.appending(path: name))
}
guard let tiff = NSBitmapImageRep.tiffRepresentationOfImageReps(in: reps, using: .lzw, factor: 0) else {
    fail("could not encode the TIFF")
}
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try tiff.write(to: output)
print("wrote \(output.path) and previews in \(previews.path)")
