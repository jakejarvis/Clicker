# Input

How presses, keys, swipes and text get from the panel to the TV. Commands all go through `RemoteController.perform`, which serializes them, so each waits for the previous one.

## Buttons

Remote buttons send the HID press on mouse-down and the release on mouse-up (`HoldButton`), so a held Siri works like the real remote.

The clickpad's four directions are not buttons. `ClickpadRingView` works out the quadrant from the pointer with `ClickpadGeometry.direction(at:)` (band by radius, quadrant by the larger of |dx| and |dy|): `onContinuousHover` sets the hovered quadrant, and a zero-distance `DragGesture` sends the press for the quadrant the press started in and the release on mouse-up wherever the pointer went. Tooltips come from one `.help` bound to the hovered quadrant. Accessibility exposes four buttons through `accessibilityChildren`, each laid out over its quadrant's bounding box; left to the default layout they stack as rows and VoiceOver outlines the wrong part of the pad. Don't make the directions four SwiftUI buttons inside the ring: `onHover` follows a button's bounding rect, not its content shape, so hover lights the wrong quadrant near the diagonals and lags.

## Keyboard

The pad's shortcuts are a focusable SwiftUI modifier on the pad (`RemoteKeyboardShortcuts`): arrows, Return for Select, Delete for Back, Space or P for Play/Pause, H or T for TV, M for Mute (only while `canMute`), + or = and − or _ for volume. Esc belongs to the panel (see [panel.md](panel.md#keys)). The keys are listed in tooltips, not in Settings.

Every key but M is held like an on-screen button: key-down sends the press (`RemoteController.keyDown`), key-up the release, and the Mac's auto-repeats are swallowed, so a held arrow scrolls and a held Return long-presses at tvOS's own rate. Don't send a press per auto-repeat: at the Mac's repeat rate the serialized queue backs up and focus keeps moving after the key is let go. The controller keeps the held set and releases all of it when the panel hides, the pad loses focus (text field, Apps picker), the device list opens or the pad leaves the screen. A key-up is handled before the modifier guard and matches shifted and unshifted characters alike, so ⌘ or Shift changing mid-hold still releases.

## Focus

The pad's shortcuts need SwiftUI focus; when nothing has it the panel window is its own first responder and every key beeps. The pad first appears while the panel is still hidden (the hosting view is loaded at init), and `showPanel` clears the first responder, so focus taken on appear is gone by the first click. Instead `RemoteController.panelAppearances` is bumped on every open, and the pad (`takeFocusIfFree`), the TV text field or the pairing `PINCodeField` (both through a `focusToken`) takes focus from it a turn later, after the clear. `padFocusRequests` hands focus back to the pad when Esc resigns the text field, since resigning alone strands it.

While either popover is open (`RemoteController.isPopoverPresented`: the Apps picker or the device list), the pad ignores keys, since the panel stays key underneath. The Apps picker also takes focus from the pad, so typing reaches its search field, and installs its own local `keyDown` monitor on appear for arrows and Return; `onKeyPress` on its `TextField` never fires in a popover here. The device list leaves the pad focused and only releases held keys.

## Trackpad swipes

A two-finger scroll over the clickpad (ring, Select and the channel between them) is a finger on the Siri Remote's touch surface.

`TrackpadSwipeMonitor` installs a local `.scrollWheel` monitor while the pad is on screen (SwiftUI has no scroll-wheel gesture outside `ScrollView`; AppKit delivers gesture scrolls to the window under the pointer without activating the app). It acts only while the pointer is over the pad in the panel window, the pad is interactive and neither popover is open, so the device and Apps popovers keep their own scrolling and a scroll over the pad doesn't move the TV's focus behind one. Each event is hit-tested against an empty AppKit view filling the pad (`PadLocator`), because an inert pad gets no hover events and a hover flag goes stale under a resting pointer. A gesture already in progress is followed to its release regardless.

`TrackpadSwipe` (pure, tested) translates the phases:

- `.began` presses at the center of the 1000-unit surface.
- `.changed` moves the finger by delta × `gain` (3 units per point, not tuned against a TV) and lifts it at the edge once the fingers carry it past one; the rest of that gesture sends nothing.
- `.ended` and `.cancelled` release. `.mayBegin` and legacy wheel notches do nothing.
- Every momentum event is dropped, so tvOS applies its own flick physics from the release velocity instead of stacking it on the Mac's.

Direction follows the fingers, not the scroll preference, since focus follows the finger on tvOS (for a list, the opposite of content following it). AppKit flips the deltas under Natural scrolling, so the finger's motion is `isDirectionInvertedFromDevice ? delta : -delta` on both axes. Settings › This Mac › Invert Swipes (`TrackpadSwipe.reversedKey`, read by the monitor through `@AppStorage` and copied into `SwipeTracking` like `isEnabled`) negates that again for people who expect a swipe to move content, independently of Natural scrolling.

`RemoteController.handleTrackpadSwipe` sends press and release through `perform` and coalesces holds to one in flight per swipe (`touchHoldQueued`, cleared by the next press and left alone by a previous swipe's hold), since trackpads report at up to 120 Hz. The controller only acts on a move or release while a press is outstanding (`touchPosition`), lifts a leftover finger before a new press, and releases in `panelDidDisappear`: the pad stays loaded while the panel is hidden, so a swipe cut off by Esc or another window never reaches the monitor's end event. The `remote` log shows `Touch down` and `Touch up ... after N holds`; holds themselves are not logged. In `--demo` all of it is a no-op, like the buttons.

The finger lifts at the edge rather than staying pinned there. Pinned, a quick flick reached the TV as a finger that stopped dead and lifted with no velocity, and focus sometimes jerked a row or two the wrong way. A per-event trace of scroll events and `_hidT` holds showed nothing reversed on our side (no delta opposed its gesture, holds went out every 8.3 ms in one direction, a quick swipe reached the edge in about 90 ms), so the jerk was probably tvOS's reaction. If it comes back, trace the same way before changing the translation.

## Text

The TV text field (`TVTextFieldView`) shows itself when the TV reports a focused field (`RemoteController.isTextFieldShown`), and the footer's keyboard button hides or re-shows it in between. The field is an `NSTextField` wrapped in `CommittedTextField`, not a SwiftUI `TextField`: it forwards text only when the field editor has no marked range, so input-method composition (CJK, dead keys such as ⌥E) reaches the TV once as committed text instead of a replace per keystroke (`--demo typing`: ⌥E then E logs one insert). It takes focus in `viewDidMoveToWindow`; Return goes through `insertNewline:` and Esc through `cancelOperation:` in the delegate, which resigns first responder so the pad's keys work again. The protocol side is in [protocol.md](protocol.md#text-input).

`PINCodeField`, for pairing, is a focusable view collecting digits with `onKeyPress`, not a hidden `TextField`: a hidden field never became first responder in the non-activating panel, so typing went nowhere.
