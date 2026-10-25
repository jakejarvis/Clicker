// Draws the release DMG's artwork into Resources/DMG/: the window background
// (background.tiff, 1x and 2x in one HiDPI TIFF, which Finder picks between)
// and the mounted disk's icon (VolumeIcon.icns). Previews land in dist/dmg/.
// Run after changing either, or the layout:
//   swift script/render_dmg_artwork.swift
//
// In the window, Clicker and Applications are two apps on the Apple TV home
// screen, and between them the remote's clickpad presses right, moving the
// focus to Applications. Finder draws icon labels in black on any background
// picture, even in Dark Mode, so the labels fall on pure black under the
// tiles, where they vanish. The disk is that clickpad on its own. Positions
// are in points from the top left and must match the icon locations in
// script/make_dmg_layout.py.
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
let captionBaseline = iconRow + 72
// The site's muted gray.
let muted = NSColor(srgbRed: 0x8f / 255, green: 0x8f / 255, blue: 0x8f / 255, alpha: 1)

let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "..").standardized
let output = directory.appending(path: "Resources/DMG")
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

/// The app's ClickpadGeometry (192 pt pad, 84 pt Select, 3 pt channel) at any
/// size.
struct Clickpad {
    let center: CGPoint
    let radius: Double

    var scale: Double { radius / 96 }
    var innerRadius: Double { 45 * scale }
    var selectRadius: Double { 42 * scale }
    var arrowRadius: Double { (innerRadius + radius) / 2 }

    /// The band around Select.
    var ring: CGPath {
        let path = CGMutablePath()
        path.addPath(circle(center, radius))
        path.addPath(circle(center, innerRadius))
        return path
    }

    var select: CGPath { circle(center, selectRadius) }

    /// The band between Select and the rim, diagonal to diagonal around `angle`.
    func quadrant(around angle: Double) -> CGPath {
        let path = CGMutablePath()
        path.addArc(
            center: center, radius: radius, startAngle: angle - .pi / 4, endAngle: angle + .pi / 4, clockwise: false)
        path.addArc(
            center: center, radius: innerRadius, startAngle: angle + .pi / 4, endAngle: angle - .pi / 4,
            clockwise: true)
        path.closeSubpath()
        return path
    }

    /// The arrows: three at rest, and the lit one pointing right, at
    /// Applications. Each is a stroked chevron shaped like the semibold SF
    /// Symbol at `pointSize`. Drawing the symbol images themselves broke at
    /// some sizes: a symbol drawn again at another size could come back as a
    /// blurred block.
    func drawArrows(_ context: CGContext, pointSize: Double, restAlpha: Double, glow: Double) {
        let depth = 0.375 * pointSize
        let halfSpan = 0.35 * pointSize
        for (angle, alpha) in [(-Double.pi / 2, restAlpha), (.pi / 2, restAlpha), (.pi, restAlpha), (0, 1)] {
            context.saveGState()
            context.translateBy(x: center.x + arrowRadius * cos(angle), y: center.y + arrowRadius * sin(angle))
            context.rotate(by: angle)
            context.move(to: CGPoint(x: -depth / 2, y: -halfSpan))
            context.addLine(to: CGPoint(x: depth / 2, y: 0))
            context.addLine(to: CGPoint(x: -depth / 2, y: halfSpan))
            context.setLineWidth(0.146 * pointSize)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setStrokeColor(white(alpha))
            if alpha == 1 { setShadow(context, blur: glow, color: white(0.8)) }
            context.strokePath()
            context.restoreGState()
        }
    }
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

/// Sets a shadow `dy` points below whatever is drawn next, blurred by `blur`
/// points. Core Graphics takes both in device pixels with y pointing up,
/// ignoring the transform, so they're converted through it; otherwise every
/// size of the icon and both scales of the background would get the same
/// pixel-sized shadow.
func setShadow(_ context: CGContext, dy: Double = 0, blur: Double, color: CGColor) {
    let scale = hypot(context.ctm.a, context.ctm.b)
    context.setShadow(offset: CGSize(width: 0, height: -dy * scale), blur: blur * scale, color: color)
}

/// A shadow cast downward.
func dropShadow(_ context: CGContext, _ path: CGPath, blur: Double, alpha: Double) {
    context.saveGState()
    setShadow(context, dy: blur * 0.45, blur: blur, color: CGColor(gray: 0, alpha: alpha))
    context.addPath(path)
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fillPath()
    context.restoreGState()
}

/// A shadow cast into `path` from its top edge, so it reads as pressed in.
func innerShadow(_ context: CGContext, _ path: CGPath, dy: Double, blur: Double, alpha: Double) {
    context.saveGState()
    context.addPath(path)
    context.clip()
    // Everything around the shape, whose shadow falls inside it.
    let surround = CGMutablePath()
    surround.addRect(path.boundingBox.insetBy(dx: -4 * blur - dy, dy: -4 * blur - dy))
    surround.addPath(path)
    setShadow(context, dy: dy, blur: blur, color: CGColor(gray: 0, alpha: alpha))
    context.addPath(surround)
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fillPath(using: .evenOdd)
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

/// A rim just inside a circle, shaded top to bottom through `colors`: bright
/// at the top for a raised surface, at the bottom lip for a pressed-in one.
func litEdge(
    _ context: CGContext, _ center: CGPoint, _ radius: Double, width: Double, _ colors: [CGColor],
    at locations: [CGFloat]
) {
    context.saveGState()
    context.addPath(circle(center, radius - width / 2))
    context.setLineWidth(width)
    context.replacePathWithStrokedPath()
    context.clip()
    let gradient = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: locations)!
    context.drawLinearGradient(
        gradient, start: CGPoint(x: 0, y: center.y - radius), end: CGPoint(x: 0, y: center.y + radius), options: [])
    context.restoreGState()
}

func drawBackground(_ context: CGContext) {
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

    // The ring, raised, and Select, pressed in: lit from below with a shadow
    // under its top edge. The channel between them stays dark, and the
    // pressed quadrant is washed like a held button in the app.
    let pad = Clickpad(center: CGPoint(x: size.width / 2, y: iconRow), radius: 46)
    fillLit(context, pad.ring, [white(0.14), white(0.07)])
    fillLit(context, pad.select, [white(0.1), white(0.12)])
    innerShadow(context, pad.select, dy: 0.5, blur: 1.2, alpha: 0.35)
    context.addPath(pad.quadrant(around: 0))
    context.setFillColor(white(0.17))
    context.fillPath()
    context.setLineWidth(1)
    context.setStrokeColor(white(0.16))
    for radius in [pad.radius - 0.5, pad.innerRadius + 0.5] {
        context.addPath(circle(pad.center, radius))
    }
    context.strokePath()
    litEdge(context, pad.center, pad.selectRadius, width: 1, [white(0.08), white(0.2)], at: [0.35, 1])
    pad.drawArrows(context, pointSize: 20 * pad.scale, restAlpha: 0.32, glow: 8)

    let font = NSFont.systemFont(ofSize: 12, weight: .medium)
    let caption = NSAttributedString(string: "Drag to install", attributes: [.font: font, .foregroundColor: muted])
    caption.draw(at: CGPoint(x: (size.width - caption.size().width) / 2, y: captionBaseline - font.ascender))
}

/// The disk: the clickpad as a dark disc on a 1024 canvas, right arrow lit.
func drawVolumeIcon(_ context: CGContext) {
    let pad = Clickpad(center: CGPoint(x: 512, y: 512), radius: 420)
    context.saveGState()
    setShadow(context, dy: 18, blur: 40, color: CGColor(gray: 0, alpha: 0.45))
    context.addPath(circle(pad.center, pad.radius))
    context.setFillColor(rgb(0x1a1a1d))
    context.fillPath()
    context.restoreGState()
    // The ring raised and lit from above; Select pressed in, lit from below
    // with a shadow under its top edge.
    fillLit(context, pad.ring, [rgb(0x46464c), rgb(0x141416)])
    fillLit(context, pad.select, [rgb(0x262629), rgb(0x2a2a2e)])
    innerShadow(context, pad.select, dy: 4, blur: 10, alpha: 0.25)
    context.addPath(pad.quadrant(around: 0))
    context.setFillColor(white(0.14))
    context.fillPath()
    litEdge(context, pad.center, pad.radius, width: 8, [white(0.45), white(0.04), white(0.12)], at: [0, 0.6, 1])
    litEdge(context, pad.center, pad.selectRadius, width: 6, [white(0.02), white(0.12)], at: [0.35, 1])
    pad.drawArrows(context, pointSize: 25 * pad.scale, restAlpha: 0.35, glow: 36)
}

/// Draws `canvas`-sized artwork into a bitmap `pixels` wide, in points from
/// the top left.
func render(_ canvas: CGSize, pixels: Int, _ draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let scale = Double(pixels) / canvas.width
    let height = Int((canvas.height * scale).rounded())
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let graphics = NSGraphicsContext(bitmapImageRep: rep)
    else { fail("could not allocate a \(pixels) px bitmap") }
    let context = graphics.cgContext
    context.translateBy(x: 0, y: Double(height))
    context.scaleBy(x: scale, y: -scale)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    draw(context)
    NSGraphicsContext.current = nil
    context.flush()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let png = rep.representation(using: .png, properties: [:]) else { fail("could not encode \(url.path)") }
    try png.write(to: url)
}

try FileManager.default.createDirectory(at: previews, withIntermediateDirectories: true)

let backgrounds = [1, 2].map { scale in
    let rep = render(size, pixels: Int(size.width) * scale, drawBackground)
    rep.size = size
    return rep
}
try writePNG(backgrounds[0], to: previews.appending(path: "background.png"))
try writePNG(backgrounds[1], to: previews.appending(path: "background@2x.png"))
guard let tiff = NSBitmapImageRep.tiffRepresentationOfImageReps(in: backgrounds, using: .lzw, factor: 0) else {
    fail("could not encode the TIFF")
}
try tiff.write(to: output.appending(path: "background.tiff"))

// The icon goes through an iconset, every size drawn from the vector art.
let iconCanvas = CGSize(width: 1024, height: 1024)
let iconset = FileManager.default.temporaryDirectory.appending(path: "VolumeIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try writePNG(render(iconCanvas, pixels: points * scale, drawVolumeIcon), to: iconset.appending(path: name))
    }
}
try writePNG(render(iconCanvas, pixels: 1024, drawVolumeIcon), to: previews.appending(path: "VolumeIcon.png"))
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", output.appending(path: "VolumeIcon.icns").path, iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fail("iconutil failed") }
try FileManager.default.removeItem(at: iconset)

print("wrote background.tiff and VolumeIcon.icns in \(output.path), and previews in \(previews.path)")
