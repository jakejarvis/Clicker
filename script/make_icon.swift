// Renders the Clicker app icon as a 1024x1024 PNG.
// Usage: swift script/make_icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.png")

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    guard let context = NSGraphicsContext.current?.cgContext else { return false }

    // Squircle background with the standard macOS icon inset.
    let inset = size * 0.1
    let plate = rect.insetBy(dx: inset, dy: inset)
    let plateRadius = plate.width * 0.2237
    let platePath = NSBezierPath(roundedRect: plate, xRadius: plateRadius, yRadius: plateRadius)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.03,
                      color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.black.setFill()
    platePath.fill()
    context.restoreGState()

    NSGradient(colors: [
        NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.30, alpha: 1),
        NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.12, alpha: 1),
    ])!.draw(in: platePath, angle: -90)

    // Subtle top highlight.
    context.saveGState()
    platePath.addClip()
    NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.14),
        NSColor.white.withAlphaComponent(0.0),
    ])!.draw(in: NSRect(x: plate.minX, y: plate.minY, width: plate.width, height: plate.height), angle: -90)
    context.restoreGState()

    // The remote body.
    let bodyWidth = plate.width * 0.30
    let bodyHeight = plate.height * 0.70
    let body = NSRect(x: rect.midX - bodyWidth / 2, y: rect.midY - bodyHeight / 2, width: bodyWidth, height: bodyHeight)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: bodyWidth * 0.26, yRadius: bodyWidth * 0.26)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.01), blur: size * 0.035,
                      color: NSColor.black.withAlphaComponent(0.5).cgColor)
    NSColor.white.setFill()
    bodyPath.fill()
    context.restoreGState()

    NSGradient(colors: [
        NSColor(calibratedWhite: 0.96, alpha: 1),
        NSColor(calibratedWhite: 0.78, alpha: 1),
    ])!.draw(in: bodyPath, angle: -90)

    // Clickpad ring near the top of the remote.
    let ringDiameter = bodyWidth * 0.78
    let ringCenter = CGPoint(x: body.midX, y: body.maxY - bodyWidth * 0.62)
    let ringRect = NSRect(x: ringCenter.x - ringDiameter / 2, y: ringCenter.y - ringDiameter / 2,
                          width: ringDiameter, height: ringDiameter)
    let ring = NSBezierPath(ovalIn: ringRect)
    NSGradient(colors: [
        NSColor(calibratedWhite: 0.70, alpha: 1),
        NSColor(calibratedWhite: 0.55, alpha: 1),
    ])!.draw(in: ring, angle: -90)

    let centerDiameter = ringDiameter * 0.46
    let centerRect = NSRect(x: ringCenter.x - centerDiameter / 2, y: ringCenter.y - centerDiameter / 2,
                            width: centerDiameter, height: centerDiameter)
    NSGradient(colors: [
        NSColor(calibratedWhite: 0.98, alpha: 1),
        NSColor(calibratedWhite: 0.86, alpha: 1),
    ])!.draw(in: NSBezierPath(ovalIn: centerRect), angle: -90)

    // Two rows of small buttons.
    let buttonDiameter = bodyWidth * 0.22
    let rowGap = bodyWidth * 0.34
    let firstRowY = ringRect.minY - bodyWidth * 0.36
    let columnOffset = bodyWidth * 0.19
    for row in 0..<3 {
        for column in [-1.0, 1.0] {
            let center = CGPoint(x: body.midX + CGFloat(column) * columnOffset,
                                 y: firstRowY - CGFloat(row) * rowGap)
            let buttonRect = NSRect(x: center.x - buttonDiameter / 2, y: center.y - buttonDiameter / 2,
                                    width: buttonDiameter, height: buttonDiameter)
            let isSiri = row == 1 && column > 0
            let colors = isSiri
                ? [NSColor(calibratedRed: 0.42, green: 0.36, blue: 0.95, alpha: 1),
                   NSColor(calibratedRed: 0.28, green: 0.22, blue: 0.80, alpha: 1)]
                : [NSColor(calibratedWhite: 0.66, alpha: 1), NSColor(calibratedWhite: 0.52, alpha: 1)]
            NSGradient(colors: colors)!.draw(in: NSBezierPath(ovalIn: buttonRect), angle: -90)
        }
    }
    return true
}

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:])
else {
    fputs("failed to render icon\n", stderr)
    exit(1)
}
try png.write(to: output)
print("wrote \(output.path)")
