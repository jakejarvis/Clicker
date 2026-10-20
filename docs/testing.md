# Testing and measuring

## Unit tests

`swift test` runs two targets. `ClickerCompanionTests` covers the protocol: OPACK and TLV8 codecs, the crypto and SRP, the text-input archive, and `CompanionConnection` cancellation against a silent loopback listener. `ClickerTests` covers the app's pure logic: panel and clickpad geometry, trackpad swipe translation, device TXT parsing, the credential store, device picker order and legacy pairing adoption. It also drives the real `RemoteController` against the demo target's made-up TVs (`DemoRun`, with pair-setup taking no time): every `--demo` scenario, pairing and re-pairing, stale pairings, mute confirmation on a real and an HDMI output, app favorites and recents, and what gets remembered for the next launch. Keep new logic testable the same way: pure, `nonisolated` value types where the UI allows, and controller behavior through `RemoteDependencies` fakes. State changes take a few task hops, so those tests wait with `eventually`.

## Looking at the panel

Build, run and look at the real panel before claiming a UI change works. [Demo mode](development.md#demo-mode) gets any state on screen without a TV.

With computer-use tools: they cannot see or grant a menu-bar-only app, so

1. `./script/build_and_run.sh --install`, then `open -n /Applications/Clicker.app --args --regular` (Dock icon). Add `--demo <scenario>` as needed.
2. Grant "Clicker" and "Finder", and bring Finder forward so the frontmost app is allowed. Zoom on the menu bar to find the remote-glyph status item (its position shifts with other status items), click it, and zoom on the panel below it.
3. Relaunch without `--regular` when done (`--install` again).

Light mode without touching the system setting: add `-NSRequiresAquaSystemAppearance YES` to the launch arguments, which forces Aqua for that process only. Increase Contrast has no such switch.

A demo panel can also be captured in the background with the computer-use `app_screenshot` tool on the app's one window, with no clicking or Finder.

Things that look like bugs but are not: zooms taken while a mouse button is held after a `wait` come back black (a capture artifact, not the panel closing), so verify presses from the `remote` log category instead. Synthetic pointer moves do trigger `.onHover`.

Things that don't work, so don't retry them: `ImageRenderer` and offscreen `cacheDisplay` snapshots drop AppKit-backed controls and Liquid Glass; `screencapture -l` needs Screen Recording permission and loses the panel's glass.

Verify keyboard focus and presses from the log (`Press Up` in the `remote` category), not by eye.

## Frame-level glitches

A control blinking for a frame or two during an animation needs a recording, not screenshots. From an unsandboxed shell (inside the sandbox it fails with `dispatch_source_create returned NULL`):

```bash
screencapture -V 8 -x out.mov
```

It records the display at up to 120 fps and starts one to five seconds after the command, so wait before acting. Then list how much each frame changed inside the panel's crop, and tile the frames around a jump:

```bash
ffmpeg -i out.mov -fps_mode passthrough -vf "crop=W:H:X:Y,tblend=all_mode=difference,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=diff.txt" -f null -
ffmpeg -i out.mov -fps_mode passthrough -vf "crop=W:H:X:Y" f%04d.png
ffmpeg -start_number N -i f%04d.png -frames:v 1 -vf "tile=4x4" tiles.png
```

(`-frames:v` counts output tiles, not input frames.) Reproduce with the real recipe: the app as an accessory (no `--regular`) and a real pointer hovering the control before the click. A flicker of the button grid once only showed up that way, never with `--regular` or with synthetic clicks that skip the hover.

## Testing against a real TV

To exercise controller paths that have no UI, add a temporary hook (a distributed-notification observer that calls `RemoteController` methods directly) to a Developer ID debug build, and remove it afterwards. Rebuild something similar rather than adding UI just to test. What has been measured this way is recorded in [protocol.md](protocol.md); what hasn't is in [unverified.md](unverified.md).

Two real copies running at once share the client identity, and the TV drops the earlier session when the second connects, so run one at a time.

## Resource usage

Launch the binary from a script so its PID is known, then:

```bash
top -l 1 -pid "$P" -stats cpu,threads,idlew,csw
footprint "$P"
vmmap -summary "$P"
leaks "$P"            # launch with MallocStackLogging=1
nettop -p "$P"
/usr/bin/log stream --level debug --predicate "processID == $P"
```

`lsof -i` shows no socket for a live session: Network.framework uses user-space channel flows. Use `nettop`.

Baseline (release build, macOS 27, Apple silicon, one TV on the network), to compare against when something changes:

- Launch: `applicationDidFinishLaunching` about 80 ms after exec, browsing at 125 ms, the TV found at 200 ms, pair-verify done about 2 s later (the TCP connect to the link-local address is the slow part). About 0.3 s of CPU for launch plus the first connection.
- Idle with the panel closed and a session up: 36 MB footprint, 5 threads, about 0.04 s of CPU per minute, 1 to 2 idle wakeups per minute, one 4-byte NoOp frame every 30 s. With the panel open (`--demo ready` or `--demo searching` with its spinner): 33 MB and no CPU growth; the spinner animates in the window server.
- Context switches with a session up run at about 11 per second, all inside Network.framework: the system's network path agents update several times a second and each update makes the connection and browser re-evaluate. The browser skips result callbacks whose changes are all `.identical`, and the status glyphs are loaded once (`StatusItemController.statusIcons`), so neither costs anything per update.

Noise that is not ours:

- A `phys_footprint_peak` of about 170 MB on every launch is GPU memory the driver attributes to the process at the first Metal context, present before the panel is shown and paged out within seconds. System menu bar apps show larger peaks.
- `leaks` reports about 400 leaked allocations (26 KB) per launch, all `NSXPCConnection` cycles from AppIntents failing to register (`Error registering app with intents framework` in the launch log), with no Clicker frame in any stack.
