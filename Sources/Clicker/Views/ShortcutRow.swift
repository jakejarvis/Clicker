import AppKit
import KeyboardShortcuts
import SwiftUI

/// The Settings row for the global shortcut: the chord as a capsule button
/// that records a new one when clicked, with a hover-revealed remove glyph
/// and a matching context-menu item, like the Forget control on a paired
/// TV. Not a text field: the package's recorder is an `NSSearchField`,
/// whose bezel differs from the Name field's by linked SDK (0.2.0 shipped
/// it as a filled capsule next to a rounded-rect field), and a chord is a
/// value you set, not text you type. Only the package's storage and
/// Carbon registration are used.
///
/// Recording: the button turns accent-tinted and reads "Press Shortcut…",
/// the registered chord is unregistered so pressing it again records
/// rather than toggles the panel, and a local key monitor takes the next
/// chord (a key with a modifier other than Shift alone, or a function
/// key), Delete to remove the current one, or Esc to cancel; every other
/// key beeps. The panel's own key monitor stands down while
/// `RemoteController.isRecordingShortcut` is set, so Esc, ⌘, and ⌘Q can
/// be recorded or cancel here instead of acting. A click anywhere but the
/// button cancels too, and so does leaving the screen.
struct ShortcutRow: View {
    let controller: RemoteController
    private let name = KeyboardShortcuts.Name.togglePanel

    @State private var shortcut = KeyboardShortcuts.getShortcut(for: .togglePanel)
    @State private var isRecording = false
    @State private var isHovered = false
    @State private var monitors: [Any] = []
    /// The button's frame in the hosting view, so a click on it does not
    /// count as a click away.
    @State private var buttonFrame: CGRect = .zero

    var body: some View {
        SettingsRow("Shortcut", help: "Opens or closes Clicker from any app. Click the shortcut, then press the keys.")
        {
            Button {
                if isRecording { stopRecording() } else { startRecording() }
            } label: {
                Text(label)
                    .font(.callout)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .frame(height: 22)
            }
            .buttonStyle(SurfaceButtonStyle(shape: Capsule(), tint: isRecording ? .accentColor : nil, pressScale: 0.98))
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                buttonFrame = $0
            }
            .help(isRecording ? "Press the keys, or Esc to cancel" : "Click, then press the keys")
            .accessibilityLabel(shortcut.map { "Shortcut: \($0)" } ?? "Record Shortcut")
            // Floated beside the button rather than laid out next to it, so
            // the row keeps its width for "Record Shortcut" while hidden.
            .overlay(alignment: .leading) {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(SurfaceButtonStyle(shape: Circle(), glass: false, pressScale: 1))
                .opacity(isHovered && shortcut != nil && !isRecording ? 1 : 0)
                .help("Remove the shortcut")
                .accessibilityLabel("Remove shortcut")
                .accessibilityHidden(shortcut == nil || isRecording)
                .offset(x: -30)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .contextMenu {
            if shortcut != nil {
                Button("Remove Shortcut", role: .destructive, action: remove)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var label: String {
        if isRecording { return "Press Shortcut…" }
        return shortcut.map { "\($0)" } ?? "Record Shortcut"
    }

    // MARK: - Recording

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        controller.isRecordingShortcut = true
        KeyboardShortcuts.disable(name)
        let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handleKey(event) }
            return nil
        }
        let clicks = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            MainActor.assumeIsolated { handleClick(event) }
            return event
        }
        monitors = [keys, clicks].compactMap { $0 }
    }

    private func stopRecording() {
        guard isRecording else { return }
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        isRecording = false
        controller.isRecordingShortcut = false
        KeyboardShortcuts.enable(name)
    }

    private func handleKey(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift, .function])
        switch event.keyCode {
        case 53 where modifiers.isEmpty:  // Escape
            stopRecording()
        case 51, 117:  // Delete, forward delete
            if modifiers.isEmpty {
                remove()
                stopRecording()
            } else {
                record(event)
            }
        default:
            record(event)
        }
    }

    private func record(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let isFunctionKey = event.specialKey.map(Self.functionKeys.contains) ?? false
        guard !modifiers.subtracting(.shift).isEmpty || isFunctionKey,
            let recorded = KeyboardShortcuts.Shortcut(event: event)
        else {
            NSSound.beep()
            return
        }
        KeyboardShortcuts.setShortcut(recorded, for: name)
        shortcut = recorded
        Log.remote.info("Recorded shortcut \(recorded, privacy: .public)")
        stopRecording()
    }

    /// A click away from the button cancels; the button's own click toggles
    /// through its action. SwiftUI's global space is the hosting view with
    /// the origin at the top, so the window point is flipped first.
    private func handleClick(_ event: NSEvent) {
        guard let contentView = event.window?.contentView else {
            stopRecording()
            return
        }
        var point = contentView.convert(event.locationInWindow, from: nil)
        if !contentView.isFlipped { point.y = contentView.bounds.height - point.y }
        if !buttonFrame.contains(point) { stopRecording() }
    }

    private func remove() {
        KeyboardShortcuts.reset(name)
        shortcut = nil
    }

    private static let functionKeys: Set<NSEvent.SpecialKey> = [
        .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19,
        .f20,
    ]
}
