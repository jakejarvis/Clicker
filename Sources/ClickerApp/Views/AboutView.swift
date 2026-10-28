import AppKit
import SwiftUI

/// Content of the About window: the icon, name and version, links to the
/// author and the source, and the copyright. Replaces the standard About
/// panel, whose credits view forces blue underlined links and whose window
/// shows minimize and zoom buttons that do nothing.
struct AboutView: View {
    @Environment(\.openURL) private var openURL
    @State private var copiedVersion = false

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                .accessibilityHidden(true)

            Text(verbatim: "Clicker")
                .font(.title2.weight(.semibold))
                .padding(.top, 10)

            versionButton
                .padding(.top, 3)

            HStack(spacing: 8) {
                link("Website", systemImage: "globe", url: AboutLinks.website)
                link("GitHub", systemImage: "chevron.left.forwardslash.chevron.right", url: AboutLinks.source)
            }
            .padding(.top, 18)

            if let copyright = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String {
                Text(copyright)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 18)
            }
        }
        .padding(.horizontal, 32)
        // The icon is centered, clear of the close button, so it may sit in
        // the title bar; its artwork has its own transparent margin.
        .padding(.top, 28)
        .padding(.bottom, 20)
        .frame(width: 280)
    }

    /// The version with its build number; a click copies it for a bug
    /// report, and the line says so for a moment.
    private var versionButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(AboutLinks.versionString, forType: .string)
            withAnimation(.easeOut(duration: 0.15)) { copiedVersion = true }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.easeOut(duration: 0.15)) { copiedVersion = false }
            }
        } label: {
            Text(copiedVersion ? "Copied" : "Version \(AboutLinks.versionString)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
        .buttonStyle(.plain)
        // It is the window's first key view, so without this it opens with
        // a focus ring around plain text.
        .focusEffectDisabled()
        .help("Copy the version")
    }

    private func link(_ title: LocalizedStringKey, systemImage: String, url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.callout)
                .labelStyle(AboutLinkLabelStyle())
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .frame(height: 28)
        }
        .buttonStyle(SurfaceButtonStyle(shape: Capsule()))
        .help(url.absoluteString)
    }
}

/// Glyph and title closer together than the default label, with a smaller glyph.
private struct AboutLinkLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
                .font(.system(size: 11, weight: .medium))
            configuration.title
        }
    }
}

/// Where the About window and the Help menu send people.
enum AboutLinks {
    static let website = URL(string: "https://clicker.jarv.is")!
    static let source = URL(string: "https://github.com/jakejarvis/Clicker")!
    /// The site's FAQ, in place of a help book.
    static let help = URL(string: "https://clicker.jarv.is/help")!
    static let issues = URL(string: "https://github.com/jakejarvis/Clicker/issues")!

    /// "0.3.6 (306)", or "dev" outside the app bundle.
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else { return "dev" }
        guard let build = info?["CFBundleVersion"] as? String, build != version else { return version }
        return "\(version) (\(build))"
    }
}
