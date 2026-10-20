# Design rules

Keep these consistent. Where an alternative is listed as rejected, it was built and looked at; don't bring it back without a new reason.

## Metrics and surfaces

- `PanelMetrics`: width 264, corner radius 14 (panel, device control, cards, overlay cards), inner radius 10 (rows, text fields, PIN digits, `PanelActionButton`, notices), horizontal padding 14.
- Interactive surfaces use `.surface(shape)`: Liquid Glass on macOS 26; on 15 a flat quaternary fill, or the tint at 18% with a tinted hairline. Static containers use `.card()` (flat quaternary fill plus hairline). Never put glass on glass for non-interactive content.
- In dark mode untinted glass is nearly the panel's own shade, so `.surface` tints it `white.opacity(0.12)` there (`SurfaceModifier.glassTint`). Light mode gets no tint, and no hairline is needed.
- Buttons use `SurfaceButtonStyle(shape:)`, never `.surface` on the outside of a `Button`. The style owns the glass: hover and press wash the whole shape with `.primary` (`SurfaceHighlight`, 10% and 18%), the control shrinks while held (`pressScale`: 0.96 by default, 0.98 for wide controls such as the device control and `PanelActionButton`, 1 for highlight-only segments), and a disabled control keeps its shape but fades its label to 40%. `glass: false` draws only the highlight, for segments inside one capsule and the flat footer controls. `Glass.interactive()` alone shows no hover or press change in this panel, which is why the highlight is explicit.
- A `Menu` using the style (Power, the footer's •••) opens on mouse-down and never reports a press, so it shows only its hover state while open, and may keep that shade until the pointer next crosses it. That is accepted. Don't fix it by observing `NSMenu` tracking notifications: that subscribed every button to every menu and caused a re-render burst on each close, in the same frame as the Settings slide.

## Glyphs

- Every remote glyph uses `RemoteMetrics.glyphFont` (16 pt medium) and an outline symbol (`playpause`, `speaker.slash`, `speaker.minus`, `speaker.plus`, `tv`, `siri`, `power`, `square.grid.2x2`, chevrons). Filled symbols next to stroked ones look several times heavier at any weight, and a per-glyph table of sizes and weights (with custom-drawn TV and plus/minus paths) looked worse than one font. Don't do either.
- Siri is the `siri` SF Symbol (macOS 26 only) in the same color and font as every other glyph; macOS 15 falls back to `mic`. Rejected: a pink-to-purple-to-blue gradient fill (no SF Symbol has a colored Siri) and `apple.intelligence` as the fallback.
- Every loading indicator is `Spinner` (the `progress.indicator` symbol with an iterative, hide-inactive variable-color effect; 16 pt in cards, 11 pt inline), never `ProgressView`, whose mid-gray fading tail nearly disappears on the dark panel and can't be tinted. `Spinner` takes the surrounding foreground style.

## The remote

From top to bottom: the device control, the clickpad with Apps and Power at its top corners, the button grid, the audio bar, the TV text field when shown, inline notices, and the footer.

- Clickpad: one glass ring (`ClickpadRing`, the disc minus Select's hole, so no glass stacks on the glass Select) with a glass Select in the middle, from `ClickpadGeometry` (192 pt pad, 84 pt Select, 3 pt channel). Nothing divides the ring at rest; the hovered or pressed quadrant is washed with a `ClickpadQuadrant` fill at the `SurfaceHighlight` opacities (hit testing is in [input.md](input.md#buttons)). The pad has its own `SurfaceContainer(spacing: 1)` so the channel around Select stays a hairline; at spacing 3 the two shapes merge into one blob. Rejected: a flat disc with secondary arrows (looked disabled), a hover disc behind each arrow, and four glass sectors with 6 pt channels (read as five objects).
- Apps (top left, a round glass `Button` opening a popover) and Power (top right, a round glass `Menu` styled by `cornerMenuStyle`) are 32 pt controls over the pad's corners. The pad is inset 16 pt below them (`RemoteMetrics.clickpadTopInset`) so the ring's top edge is level with their centers; the overlay cards share the inset so they stay centered on the pad. Power's `Menu` needs `.menuStyle(.button)` with `SurfaceButtonStyle(shape: Circle())`, `.menuIndicator(.hidden)` and `.fixedSize()`; `.borderlessButton` ignores the label frame.
- Below the pad, a 2×2 grid of capsules: Back and TV on the navigation row, Play/Pause and Siri on the media row, with the `SurfaceContainer`'s 10 pt spacing. Build it from two `HStack`s, never a `LazyVGrid`: the lazy grid dropped its rows for a few frames as the remote slid out to Settings, so the capsules blinked.
- The audio bar (`AudioBar`) is one full-width capsule split into Mute, volume down and volume up by hairline dividers, in the order of the Mac's media keys. Segments are highlight-only (`glass: false`, `pressScale` 1) so pressing one doesn't move the rest, and Mute tints only its own segment orange (`MuteSegment`) so the tint reads as mute, not volume. The volume glyphs are `speaker.minus` and `speaker.plus`, so the bar is three speakers differing only in their badge; `speaker.wave.1`/`.3` read as levels and the three-wave glyph is wider.
- The TV text field sits below the grid, not above the clickpad: the panel is anchored at its top and grows downward, so a keyboard appearing on the TV never moves a button. A card over the pad was set aside because the pad may still be needed while typing, and an always-available keyboard button that opened an inert field without a session was rejected.
- Footer: the keyboard button on the left (hides or re-shows the text field; accent-tinted while it shows; enabled only while the TV reports a focused field) and the ••• menu (tooltip "Menu") on the right. The keyboard button's `.help` sits outside `.disabled` with a `contentShape`, since a disabled button takes no hover and would lose its tooltip. No footer tooltip shows while the text field has focus. Quit is only ever in menus, never a button.
- State wording in the device control: connected and on is "Ready", connected and off is "Asleep".

## When the remote can't be used

The remote is always drawn. When it can't be used (unpaired, offline, no TVs found, none chosen) `MenuBarView` dims it to 35%, blurs it 2 pt, makes it inert (`RemotePadView(isInteractive: false)`: no hit testing, no keyboard focus) and centers an `OverlayCard` over the clickpad (`RemoteOverlayCards.swift`). Cards are `.regularMaterial` with a hairline and a shadow, 212 pt wide: a headline, one caption and at most one row of buttons. Pairing morphs in place: Pair → spinner → `PINCodeField` → green check (`PairingState.succeeded`, 1.2 s) → the remote un-ghosts.

A paired, online TV without a session (connecting, failed or closed) gets no card: the remote is dimmed to 50% without blur and is inert and `.disabled`, the device picker's subtitle says Connecting…, Connection failed or Not connected, and the latter two add a notice with Retry or Connect. Presses used to be accepted then and queued for the session, which looked like the remote working while nothing reached the TV, and were dropped when the connect failed. `--demo connecting` shows it. When macOS denies the local network the subtitle is No local network access and the notice says where to turn Clicker on, with a full-width Open Privacy & Security button under the message in place of Retry (`--demo localnetwork`; see [protocol.md](protocol.md#connection-lifecycle)).

Inline notices (`InlineNoticeView`, built from `InlineNotice` values in `MenuBarView.notices`) sit below the remote and stack, problems first: the connection or failed-action notice (orange warning, only while the remote is live, since otherwise a card explains it) and the pending update (accent `arrow.down.circle.fill`, shown even behind a card so an unpaired or sleeping TV doesn't hide it). `--demo notices` shows both. A notice's action sits beside the message (`InlineNotice.Action.Placement.trailing`), or under it at full width (`.below`) when the message needs the panel's width: beside a long message the button squeezed it into three truncated lines. The pending update is only ever this notice and the menus' Update to X… item; a dot on the status item, an accent glyph in the footer and a prominent footer capsule were all tried and dropped.

## Device picker

A full-width control with a popover list; it is custom because a system `Menu` can't show subtitles.

- Rows are in `RemoteController.pickerOrder`: paired and online, then paired but offline, then unpaired, by name within each group, like the Wi-Fi menu. The selected TV has a check mark and is not floated to the top, so the list never jumps when switching.
- Hover and the arrow keys move one highlight (the `.rowHighlight` fill, like the Apps picker) and Return picks the highlighted TV; only arrows scroll. The keys ride a local `keyDown` monitor while the list is up. The rows and Rescan are `.focusable(false)`: a focusable row took focus when the list opened, unseen, and Space picked it whatever the highlight said.
- ⌥-click opens the same popover in details mode, like the Wi-Fi menu. The mode is read in the button action from the click event's own flags (`NSApp.currentEvent`, which synthetic clicks carry too) unioned with `NSEvent.modifierFlags`. The popover is `.popover(item:)` with the mode on the item (`DevicePickerPresentation`, held in `RemoteController.devicePickerPresentation` so `panelDidDisappear` drops it and Esc closes it). An `isPresented` popover whose content reads a second `@State` set in the same action renders with the stale value.
- In details mode each row is followed by caption `Label: value` lines (`DeviceDetailsView`): Model, ID, Bluetooth, tvOS (connected TV only), Protocol, Flags, Interface, then for the connected TV Address and Session, then Power and Controls. The list widens to `PanelMetrics.width + 56` so a UUID fits, and a Rescan row sits at the bottom (see [protocol.md](protocol.md#discovery)). Rescan appears nowhere else.

## Apps picker

`AppPickerView` is a popover: a search field over a list capped at 300 pt, with Favorites, Recents and All Apps groups. The list spans the popover edge to edge and insets only its content (`contentMargins(.horizontal, 6, for: .scrollContent)`), so the overlay scroller rides in the popover's margin instead of covering the stars. A fixed trailing gutter for the scroller was rejected: overlay scrollers hide when idle, which left the rows off-center.

- Favorites are starred bundle IDs per TV in the order starred (`favoriteAppIDsByDevice`). Recents are the last five launched per TV (`recentAppIDsByDevice`), minus the favorites. Both are keyed by device id, follow `rekey`, go on Forget and are resolved against the TV's current list. The Recents header has a tertiary Clear button (`RemoteController.clearRecents`, current TV only).
- Every row ends in a star button (outline while the row is highlighted, yellow and filled once starred), a sibling of the launch button so a click on it never launches; the context menu offers the same toggle, and starring leaves the popover open.
- Typing filters (prefix matches first) and highlights the top match so Return launches it. Hover and arrows move the highlight; only arrows scroll. Rows use the `.rowHighlight` fill like device rows.
- The popover is centered on the Apps button so its arrow points at it, which puts the list past the panel's left edge. Anchoring it to a rect spanning the pad (arrow floating mid-pad) was rejected, and so was a system `Menu` (forty rows with scroll arrows and no search).

## Settings

- Section headers `.subheadline.semibold` secondary; row titles `.body`; secondary text `.caption`. Rows are 40 pt minimum with 12/8 padding and a hairline `SettingsDivider` between them.
- The Name field is the system `.roundedBorder` text field, the only text field in Settings; the shortcut is a button ([panel.md](panel.md#global-shortcut)).
- A row's action is a hover-revealed, highlight-only glyph button with a matching context-menu item (Forget's `xmark.circle.fill`). Every toggle is a small `.switch`.
- Explanations go in section footers, or behind a row's `info.circle` with a `.help` tooltip (`SettingsRow(help:)`, used by Name and Shortcut) when they belong to one row. Never inline text.
- This Mac is Name, Shortcut, Invert Swipes and Open at Login (named to match System Settings › Login Items).
- Full-width actions at the end use `PanelActionButton` (30 pt, callout, primary text); Check for Updates lives there. Settings only offers Check Automatically for updates ([releasing.md](releasing.md#updates-in-the-app)).
