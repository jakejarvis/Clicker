// Converts Resources/StatusIcon/*.svg into the PDFs the app loads as menu bar
// template images. Run after replacing an SVG:
//   swift script/make_status_icons.swift
//
// Both glyphs are cropped to the union of their ink bounds (so the status item
// keeps its width when the state changes) and scaled to `height` points.
import AppKit

let height = 16.0
let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appending(path: "../Resources/StatusIcon").standardized
let pairs = ["Connected", "Disconnected"].map {
    (directory.appending(path: "\($0).svg"), directory.appending(path: "\($0).pdf"))
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

/// Bounds of the non-transparent pixels, in the image's own point space.
func inkBounds(of image: NSImage) -> NSRect {
    let scale = 32.0
    let width = Int(image.size.width * scale)
    let rows = Int(image.size.height * scale)
    guard
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: rows, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)
    else { fail("could not allocate bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(x: 0, y: 0, width: width, height: rows))
    NSGraphicsContext.restoreGraphicsState()

    var minX = width, maxX = -1, minY = rows, maxY = -1
    let data = bitmap.bitmapData!
    for y in 0..<rows {
        for x in 0..<width where data[y * width * 4 + x * 4 + 3] > 0 {
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
        }
    }
    guard maxX >= 0 else { fail("image has no visible pixels") }
    // Bitmap rows run top to bottom; flip into AppKit's bottom-left space.
    return NSRect(
        x: Double(minX) / scale, y: image.size.height - Double(maxY + 1) / scale,
        width: Double(maxX - minX + 1) / scale, height: Double(maxY - minY + 1) / scale)
}

let images = pairs.map { input, _ in
    guard let image = NSImage(contentsOf: input) else { fail("could not load \(input.path)") }
    return image
}
let bounds = images.map(inkBounds)
let crop = bounds.dropFirst().reduce(bounds[0]) { $0.union($1) }
let scale = height / crop.height
var mediaBox = CGRect(x: 0, y: 0, width: (crop.width * scale).rounded(.up), height: height)

for (image, (_, output)) in zip(images, pairs) {
    guard let context = CGContext(output as CFURL, mediaBox: &mediaBox, nil) else { fail("could not create \(output.path)") }
    context.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    // Center horizontally in the rounded-up width.
    let inset = (mediaBox.width - crop.width * scale) / 2
    image.draw(
        in: NSRect(
            x: inset - crop.minX * scale, y: -crop.minY * scale,
            width: image.size.width * scale, height: image.size.height * scale))
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()
    print("wrote \(output.lastPathComponent) (\(Int(mediaBox.width))x\(Int(mediaBox.height)) pt)")
}
