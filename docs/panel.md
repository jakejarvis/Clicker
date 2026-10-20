# The panel

## Why not MenuBarExtra

`MenuBarExtra`'s window is SwiftUI-internal chrome, with no control over its corner radius, size animation or key status. The app uses an `NSStatusItem` plus a borderless, non-activating `NSPanel` that overrides `canBecomeKey`, so keystrokes work without activating the app (the approach is modeled on robinebers/openusage).

## Window

- Backdrop: `NSGlassEffectView` on macOS 26, a behind-window `NSVisualEffectView` with a rounded mask on macOS 15. The SwiftUI host layer is clipped to `PanelMetrics.cornerRadius`. Clear glass stays: an opaque tray filled with `windowBackgroundColor` read as flat in dark mode, and glass tinted toward the window color (`NSGlassEffectView.tintColor` at 0.5 to 0.7 alpha) put a color wash over the vibrancy.
- Placement: the panel hangs from the status item's left edge, like a status item's menu (`PanelGeometry.topLeft`), clamped to the screen.
- Height: SwiftUI drives it, one frame at a time (`PanelHeightBridge.swift`). `MenuBarView` pins its container to the natural height of the screen being shown (remote or Settings) and attaches `drivesPanelHeight`, an identity `GeometryEffect` whose `animatableData` is that height. Inside a `withAnimation`, SwiftUI sets it once per frame with the interpolated value; the bridge hops it to the next main-queue turn (a `setFrame` from inside the layout pass re-enters AppKit layout) and `StatusItemController.applyHeight` sets the frame, anchored top-left and clamped to the screen, with no AppKit animation at all. The window and the screen slide therefore move on one curve. The shadow is invalidated once the frames stop (120 ms). The first Settings visit establishes `settingsHeight` inside a `withAnimation`, because the measurement lands a frame after the switch began, outside its transaction. Don't go back to `preferredContentSize` plus an `NSAnimationContext` resize: two animations with different curves, retargeted every frame, visibly disagree.
- `hosting.sizingOptions` must be `[]`. With an intrinsic content size, autolayout grows the window to the taller screen the moment it mounts (its compression resistance outranks the window's own size) and the rendered content shifts down for a frame.
- The opening measurement is `sizeThatFits(in: width × 0)`: an unbounded proposal is answered unbounded (the root fills what it is offered) and opens the panel at the screen's height for a frame.

## Keys

A local `keyDown` monitor handles the panel's own keys, only when the event's window is the panel:

- Esc closes, in order: the Apps picker or the device popover, then Settings, then an in-progress pairing, then the panel (`RemoteController.handleEscape`). Esc is left alone while an `NSText` is first responder, so the text field's `cancelOperation:` gets it.
- ⌘, opens Settings and ⌘Q quits.
- The monitor returns early while a shortcut is being recorded, so ⌘, and ⌘Q record rather than act.

SwiftUI `.keyboardShortcut` is unreliable in this panel; don't rely on it. The remote's own keys are covered in [input.md](input.md#keyboard).

## Global shortcut

The Shortcut row in Settings › This Mac (`ShortcutRow`) records a chord that opens or closes the panel from any app. It goes through `KeyboardShortcuts` (`KeyboardShortcuts.Name.togglePanel` in `PanelHotKey.swift`, handler in `StatusItemController.installHotKey`), which uses Carbon's `RegisterEventHotKey`, the only global hotkey that needs no permission (`NSEvent` global monitors and `CGEventTap` want Accessibility or Input Monitoring). The handler calls `togglePanel`, the same path as a click on the status item, so the panel opens without activating Clicker and the pad takes focus the usual way. There is no default chord. The package stores it in user defaults under `KeyboardShortcuts_togglePanel`, in the real domain even under `--demo`.

Only the package's storage and registration are used (`getShortcut`, `setShortcut`, `reset`, `disable`/`enable`, `Shortcut(event:)` and the chord's `description`). Recording is ours:

- The control is a `SurfaceButtonStyle` capsule showing the chord or "Record Shortcut", with a hover-revealed `xmark.circle.fill` floated beside it in an overlay (laid out inline it truncated the label) and a Remove Shortcut context-menu item.
- Clicking it sets `RemoteController.isRecordingShortcut`, tints the button accent with "Press Shortcut…", unregisters the current chord through `disable` (otherwise pressing it again toggles the panel instead of recording), and installs local monitors.
- keyDown accepts a key with a modifier other than Shift alone, or a function key (`Shortcut(event:)`); Delete removes, Esc cancels, anything else beeps, and every key is swallowed.
- A mouse-down outside the button's frame cancels (the frame comes from `onGeometryChange` in `.global`, which on macOS is the hosting view with the origin at the top, so the window point is flipped), and so does leaving the screen.

Don't use the package's `KeyboardShortcuts.Recorder`. It is an `NSSearchField` rigid at a 130 pt intrinsic width, which overflowed the panel; its clear button never worked in this panel (its `becomeFirstResponder` installs a monitor that swallows the mouse-up); and its bezel depends on the linked SDK, so the shipped look differed from local builds. A chord is a value you set, not text you type, so a button fits anyway.

## Dismissal

Local and global mouse-down monitors (`PanelOutsideClickMonitor`) close the panel on outside clicks, except clicks on the status button, inside the panel, in menu or popover windows, or while `panel.attachedSheet != nil`. `RemoteController.dismissPanel` hides it from code (About uses it).

## First launch

`AppDelegate` opens the panel itself half a second after launch while `hasCompletedFirstLaunch` is unset in user defaults, so a new user sees the Looking for Apple TVs card and then the pair card without hunting for the icon. The flag is recorded only after the panel actually opened, and it is per user, not per install. The Local Network prompt can land at the same time, and a click on it closes the panel as an outside click; that is accepted. Demo runs open the panel the same way on every launch. Launching the app again while it runs (`applicationShouldHandleReopen`) opens the panel.

## Menus and popovers

- Right-click or control-click on the status item: Settings…, Check for Updates… (Update to X… while one is pending), About Clicker, Quit Clicker. The footer's ••• menu (`AppMenu`, a SwiftUI `Menu`) has the same items. About opens the standard About panel (`AboutPanel`), hiding the panel first.
- SwiftUI `.popover` and `.alert` work inside the panel (the device picker, the Apps picker and the Forget confirmation use them). The panel stays the key window under a popover: key events go to the panel's focused SwiftUI view, and only keys it ignores fall through to a text field in the popover.
- On macOS 26 and later both popovers' content gets `.popoverAppearance()` (`PopoverAppearance`, in `App/`). SwiftUI still gives popover windows the vibrant appearance the pre-glass popover material blended, and a glass popover blends nothing, so AppKit drew vibrant colors opaque: an overlay scroller's track came out solid `#141414` when hovered. The bridge sets the window to the plain appearance matching the app's (`darkAqua`, `aqua` or their high-contrast versions; it reads `NSApp.effectiveAppearance`, because the window's own would echo back an appearance pinned by an earlier presentation). Setting only the scroller's appearance doesn't stick, and setting the window's to `nil` brings vibrant back. macOS 15 keeps the vibrant appearance, which its popover material does blend. Row highlights in both popovers are `.rowHighlight` (`selectedContentBackgroundColor`, in `Surface.swift`), not `.selection`: the popover window is never key, so `.selection` drew the gray inactive fill, white on near-white in light mode, and overriding the content's `controlActiveState` to `.key` didn't change that. In light mode the popovers draw dark text, the blue highlight and a translucent scroller track.
- Every `.help` in the panel is an AppKit tooltip, whose initial delay is the `NSInitialToolTipDelay` user default in milliseconds. `AppDelegate` registers 300 at launch (registration domain, nothing persisted), because the system's roughly one-second delay made the row info glyphs and clickpad hints feel absent.
- While a Sparkle window is up the app switches to `.regular` and hides the panel (it floats at pop-up menu level), then restores the launch activation policy, so `--regular` keeps working.
