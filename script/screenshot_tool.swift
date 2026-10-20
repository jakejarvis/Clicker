// Helper for script/screenshots.sh, which compiles it. Subcommands:
//   check                  exit 1 (and ask macOS) unless this terminal may record the screen
//   wait-clear <seconds>   wait until no app has a window on the main display
//   park-pointer           move the pointer away from the status item and the panel
//   frame --pid P --clean C --shot S --out O --headline H [--subhead T] [--keep-menu-bar]
//
// `frame` turns a full-display capture of the demo panel into an App Store
// screenshot: a 1440×900-point (or 1280×800) region of the real screen at its
// own scale, never resampled, with the menu bar emptied except for Clicker's
// item, and a caption to the left of the panel. `--clean` is the same display
// captured with Clicker not running, which tells Clicker's item apart from
// the menu bar under it. The panel's Liquid Glass only survives a
// full-display capture (docs/testing.md), so this works from captures rather
// than drawing the window itself.
import AppKit
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("screenshot_tool: " + message + "\n").utf8))
    exit(1)
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard !arguments.isEmpty else { fail("missing subcommand") }
let subcommand = arguments.removeFirst()

func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

func requiredOption(_ name: String) -> String {
    guard let value = option(name) else { fail("\(subcommand) needs \(name)") }
    return value
}

guard let screen = NSScreen.screens.first else { fail("no display") }
/// The display with the menu bar, in points with the origin at the top left,
/// as CGWindowList and the captures use.
let screenSize = screen.frame.size

switch subcommand {
case "check":
    guard CGPreflightScreenCaptureAccess() else {
        CGRequestScreenCaptureAccess()
        fail(
            "this terminal can't record the screen. Allow it in System Settings › Privacy & Security › "
                + "Screen & System Audio Recording, restart the terminal and run the script again.")
    }

case "wait-clear":
    waitForClearScreen(timeout: Double(arguments.first ?? "") ?? 120)

case "park-pointer":
    // The pointer itself is never in a capture, but where it rests shows as
    // a hover state; the left half of the screen is clear of the panel.
    CGWarpMouseCursorPosition(CGPoint(x: screenSize.width * 0.25, y: screenSize.height * 0.5))

case "frame":
    frame()

default:
    fail("unknown subcommand \(subcommand)")
}

// MARK: - A clear screen

/// The apps with an ordinary window showing on the main display. The panel
/// shows whatever is behind its glass, and anything there would end up in a
/// public screenshot.
func appsWithWindows() -> [String] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
    let display = CGRect(origin: .zero, size: screenSize)
    let owners = (list as? [[String: Any]] ?? []).compactMap { window -> String? in
        guard window[kCGWindowLayer as String] as? Int == 0,
            (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
            let bounds = window[kCGWindowBounds as String] as? NSDictionary,
            let rect = CGRect(dictionaryRepresentation: bounds), rect.intersects(display)
        else { return nil }
        return window[kCGWindowOwnerName as String] as? String ?? "an app"
    }
    return Array(Set(owners)).sorted()
}

func waitForClearScreen(timeout: Double) {
    let deadline = Date.now.addingTimeInterval(timeout)
    var reported: [String] = []
    while true {
        let owners = appsWithWindows()
        if owners.isEmpty { return }
        if owners != reported {
            print("Waiting for these to close or hide (⌘H): \(owners.joined(separator: ", "))")
            reported = owners
        }
        if Date.now > deadline { fail("windows still on screen after \(Int(timeout)) seconds") }
        Thread.sleep(forTimeInterval: 0.5)
    }
}

// MARK: - Framing

func frame() {
    guard let pid = Int32(requiredOption("--pid")) else { fail("--pid must be a process ID") }
    let shot = loadImage(requiredOption("--shot"))
    let clean = loadImage(requiredOption("--clean"))
    guard shot.width == clean.width, shot.height == clean.height else {
        fail("the clean capture and the shot have different sizes; did the display change?")
    }
    let scale = CGFloat(shot.width) / screenSize.width
    guard abs(CGFloat(shot.height) / screenSize.height - scale) < 0.01 else {
        fail("the capture isn't of the main display")
    }
    let pixels = { (points: CGFloat) in Int((points * scale).rounded()) }

    let windows = clickerWindows(pid: pid)
    guard let panel = windows.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
        fail("Clicker (pid \(pid)) has no window on screen; did the panel open?")
    }
    let content = windows.reduce(panel) { $0.union($1) }

    let canvas = canvasSize()
    let origin = CGPoint(x: screenSize.width - canvas.width, y: 0)
    guard content.maxY <= canvas.height - 16, content.minX >= origin.x + 400 else {
        fail(
            "the panel (\(content)) doesn't fit a \(Int(canvas.width))×\(Int(canvas.height))-point frame beside a caption"
        )
    }

    let shotBitmap = Bitmap(shot)
    let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
    // The panel's top edge can reach into the menu bar's last row.
    let bar = min(pixels(menuBarHeight), pixels(panel.minY) - 1)
    if !arguments.contains("--keep-menu-bar"), bar > 0 {
        let cleanBitmap = Bitmap(clean)
        // Clicker's item starts at the panel's left edge (PanelGeometry.topLeft)
        // and ends where the menu bar matches the clean capture again: the items
        // to its right are anchored to the right and don't move when it quits.
        let itemStart = max(0, pixels(panel.minX) - pixels(4))
        let itemEnd = shotBitmap.firstMatchingColumn(
            with: cleanBitmap, from: pixels(panel.minX + 8), to: pixels(panel.minX + 160), rows: 0..<bar,
            run: pixels(6))
        shotBitmap.emptyMenuBar(rows: bar, keeping: itemStart..<min(shot.width, itemEnd), over: cleanBitmap)
    }

    let width = pixels(canvas.width)
    let height = pixels(canvas.height)
    let context = makeContext(width: width, height: height, colorSpace: shot.colorSpace)
    // Core Graphics counts up from the bottom: line the capture's top row up
    // with the frame's, `origin.x` points in.
    context.draw(
        shotBitmap.image(),
        in: CGRect(x: -pixels(origin.x), y: height - shot.height, width: shot.width, height: shot.height))
    // From here on, the captures' top-left origin.
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)

    let margin = 96 * scale
    let captionWidth = (content.minX - origin.x) * scale - margin - 96 * scale
    drawCaption(
        in: context, headline: requiredOption("--headline"), subhead: option("--subhead"), scale: scale,
        frame: CGRect(x: margin, y: 0, width: captionWidth, height: CGFloat(height)),
        centerY: (content.midY - origin.y) * scale)

    write(context.makeImage()!, to: requiredOption("--out"))
}

/// 1440×900 points where the display has room, else 1280×800: at 2x these
/// are the App Store's 2880×1800 and 2560×1600.
func canvasSize() -> CGSize {
    for size in [CGSize(width: 1440, height: 900), CGSize(width: 1280, height: 800)]
    where screenSize.width >= size.width && screenSize.height >= size.height {
        return size
    }
    fail("the display is \(Int(screenSize.width))×\(Int(screenSize.height)) points; it needs at least 1280×800")
}

/// The on-screen windows of `pid`: the panel, and any popover or menu open over it.
func clickerWindows(pid: Int32) -> [CGRect] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.compactMap { window -> CGRect? in
        guard window[kCGWindowOwnerPID as String] as? Int32 == pid,
            let bounds = window[kCGWindowBounds as String] as? NSDictionary,
            let rect = CGRect(dictionaryRepresentation: bounds), rect.width > 1, rect.height > 1
        else { return nil }
        return rect
    }
}

/// White, in the system font, vertically centered on `centerY` where it fits.
/// `\n` in either string breaks the line there, within the paragraph.
func drawCaption(
    in context: CGContext, headline: String, subhead: String?, scale: CGFloat, frame: CGRect, centerY: CGFloat
) {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 12 * scale
    shadow.shadowOffset = .zero
    let headlineStyle = NSMutableParagraphStyle()
    headlineStyle.lineSpacing = 2 * scale
    let text = NSMutableAttributedString(
        string: headline.replacingOccurrences(of: "\\n", with: "\u{2028}"),
        attributes: [
            .font: NSFont.systemFont(ofSize: 52 * scale, weight: .bold), .foregroundColor: NSColor.white,
            .shadow: shadow, .paragraphStyle: headlineStyle,
        ])
    if let subhead, !subhead.isEmpty {
        let subheadStyle = NSMutableParagraphStyle()
        subheadStyle.paragraphSpacingBefore = 20 * scale
        subheadStyle.lineSpacing = 4 * scale
        text.append(
            NSAttributedString(
                string: "\n" + subhead.replacingOccurrences(of: "\\n", with: "\u{2028}"),
                attributes: [
                    .font: NSFont.systemFont(ofSize: 24 * scale, weight: .medium),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.85), .shadow: shadow,
                    .paragraphStyle: subheadStyle,
                ]))
    }
    let bounds = text.boundingRect(
        with: CGSize(width: frame.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin])
    let top = min(max(centerY - bounds.height / 2, 64 * scale), frame.maxY - bounds.height - 64 * scale)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    text.draw(
        with: CGRect(x: frame.minX, y: top, width: frame.width, height: bounds.height),
        options: [.usesLineFragmentOrigin])
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Images

func loadImage(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { fail("can't read \(path)") }
    return image
}

func outputSpace(_ colorSpace: CGColorSpace?) -> CGColorSpace {
    colorSpace.flatMap { $0.supportsOutput ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
}

/// No alpha channel: App Store Connect refuses screenshots that have one.
func makeContext(width: Int, height: Int, colorSpace: CGColorSpace?) -> CGContext {
    guard
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: outputSpace(colorSpace), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { fail("can't make a \(width)×\(height) bitmap") }
    return context
}

func write(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fail("can't write \(path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("can't write \(path)") }
}

/// A capture's pixels as RGBX bytes, top row first.
final class Bitmap {
    let width: Int
    let height: Int
    let colorSpace: CGColorSpace?
    var bytes: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        colorSpace = image.colorSpace
        bytes = [UInt8](repeating: 0, count: width * height * 4)
        let (width, height, space) = (width, height, outputSpace(colorSpace))
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func offset(_ column: Int, _ row: Int) -> Int { (row * width + column) * 4 }

    /// How far apart two pixels are: the largest difference in any channel.
    private func distance(_ column: Int, _ row: Int, _ other: Bitmap) -> Int {
        let at = offset(column, row)
        return (0..<3).map { abs(Int(bytes[at + $0]) - Int(other.bytes[at + $0])) }.max()!
    }

    /// The first column in `from..<to` that starts `run` columns in a row
    /// where every pixel in `rows` is close to `other`'s.
    func firstMatchingColumn(with other: Bitmap, from: Int, to: Int, rows: Range<Int>, run: Int) -> Int {
        var matched = 0
        for column in from..<min(to, width) {
            matched = rows.allSatisfy { distance(column, $0, other) <= 12 } ? matched + 1 : 0
            if matched == run { return column - run + 1 }
        }
        return min(to, width)
    }

    /// Paints each of the top `rows` rows in its own background color (its
    /// median, which the sparse menu titles and icons don't move), then lays
    /// back the pixels in `keeping` that differ from `clean`, the menu bar
    /// without Clicker: its item, blended in by how much it differs, so the
    /// glyph's soft edges survive.
    func emptyMenuBar(rows: Int, keeping: Range<Int>, over clean: Bitmap) {
        for row in 0..<rows {
            let background = (0..<3).map { channel in
                var values = stride(from: 0, to: width, by: 2).map { clean.bytes[offset($0, row) + channel] }
                values.sort()
                return values[values.count / 2]
            }
            for column in 0..<width {
                let at = offset(column, row)
                let weight = keeping.contains(column) ? min(1, Double(distance(column, row, clean)) / 48) : 0
                for channel in 0..<3 {
                    let kept = Double(bytes[at + channel]) * weight + Double(background[channel]) * (1 - weight)
                    bytes[at + channel] = UInt8(kept.rounded())
                }
            }
        }
    }

    func image() -> CGImage {
        CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: outputSpace(colorSpace), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent)!
    }
}
