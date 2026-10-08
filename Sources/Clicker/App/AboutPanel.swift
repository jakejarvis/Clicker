import AppKit

/// Presents the standard macOS About panel. The panel takes the icon, name,
/// version and copyright from the bundle; only the credits are supplied here.
///
/// Clicker is an accessory app and is not active while the panel is open, so
/// it activates first; otherwise the About window opens behind the frontmost
/// app. Callers hide the menu bar panel beforehand, since it floats at pop-up
/// menu level and would cover the window.
enum AboutPanel {
    @MainActor
    static func present() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    private static var credits: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]

        let credits = NSMutableAttributedString()
        credits.append(NSAttributedString(string: "Created by ", attributes: base))
        credits.append(link("Jake Jarvis", "https://jarv.is", base: base))
        credits.append(NSAttributedString(string: "\n\nOpen source on ", attributes: base))
        credits.append(link("GitHub", "https://github.com/jakejarvis/Clicker", base: base))
        return credits
    }

    private static func link(_ text: String, _ urlString: String, base: [NSAttributedString.Key: Any])
        -> NSAttributedString
    {
        var attributes = base
        if let url = URL(string: urlString) {
            attributes[.link] = url
        }
        return NSAttributedString(string: text, attributes: attributes)
    }
}
