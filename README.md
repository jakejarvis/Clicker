# Clicker

An Apple TV remote that lives in your Mac's menu bar.

A small native app with the Siri Remote's buttons, plus typing, app launching and keyboard control. It talks to the Apple TV directly over your network, with no accounts, helper apps or cloud service.

Requires macOS 15 or later.

## Install

1. Download `Clicker-X.Y.Z.dmg` from the [latest release](https://github.com/jakejarvis/Clicker/releases/latest).
2. Open it and drag Clicker to your Applications folder.
3. Open Clicker. Its icon appears in the menu bar; there is no Dock icon or window.

The first time it runs, macOS asks whether Clicker may find devices on your local network. Allow it, or Clicker can't see your Apple TV.

Clicker is signed and notarized by Apple, and keeps itself up to date (see [Updates](#updates)).

## Pair with your Apple TV

You only do this once per Apple TV.

1. Make sure your Mac and Apple TV are on the same network, and that the Apple TV is awake.
2. Click Clicker in the menu bar. If you have more than one Apple TV, pick one from the list at the top.
3. Click **Pair…**. A four-digit code appears on your TV.
4. Type the code. Clicker connects as soon as you enter the last digit.

That's it. From now on Clicker connects on its own whenever you open it.

If the Apple TV won't pair, check **Settings › Remotes and Devices › Remote App and Devices** on the TV.

## Using the remote

- **Clickpad**: click the arrows to move around and the center to select.
- **Siri**: hold the button down, just like the real remote.
- **Volume and Mute** (the bar along the bottom) control your TV or receiver if the Apple TV does (through HDMI-CEC or an IR remote it learned).
- **Apps** (top-left corner of the clickpad): search your Apple TV's apps and open one. The ones you open most recently are at the top.
- **Power** (top-right corner): Wake, Sleep, Screen Saver and Control Center.
- **Typing**: when a search box or password field is showing on the TV, a text field appears at the bottom of the panel. Type there and the text shows up on your TV. The keyboard button in the bottom corner hides it or brings it back.
- **Switching TVs**: click the Apple TV's name at the top of the panel.

### Keyboard shortcuts

While the panel is open you can leave the mouse alone:

| Key | Does |
|---|---|
| Arrow keys | Move |
| Return | Select |
| Delete | Back |
| Space | Play/Pause |
| H | TV (Home) |
| M | Mute |
| + and − | Volume up and down |
| ⌘, | Settings |
| Esc | Close the panel |

Hover over any button to see its shortcut.

## Settings

Open Settings from the ••• menu in the bottom corner of the panel, by right-clicking the menu bar icon, or with ⌘,. There you can:

- change the name your Apple TV shows for this Mac under Remotes and Devices,
- start Clicker when you log in,
- forget an Apple TV you've paired, and
- choose whether to check for updates automatically.

## Updates

Clicker checks for a new version once a day. When one is ready, a dot appears on the menu bar icon and an update button shows up in the panel. You can also check yourself with **Check for Updates…** in the ••• menu or by right-clicking the menu bar icon. Turn the daily check off in Settings.

## Privacy

Clicker only talks to Apple TVs on your own network. It doesn't collect analytics, and the only other connection it makes is the daily update check. Pairing keys are stored in your Mac's keychain and can only be read by Clicker; **Forget** in Settings removes them.

## Troubleshooting

- **Stuck on "Looking for Apple TVs…"**: make sure the Mac and Apple TV are on the same network, and that Clicker is allowed in **System Settings › Privacy & Security › Local Network**.
- **"Not on this network right now"**: wake the Apple TV with its own remote and check that it's on the same network as your Mac. An Apple TV that was just plugged in can take a minute to show up.
- **Pairing fails**: check the TV's **Remotes and Devices** settings (see above) and try again.
- **A paired Apple TV stops responding**: forget it in Clicker's Settings and pair again. This is also needed if you removed Clicker from the TV's list of remotes.

## Contributing

Clicker is a native SwiftUI app with no dependencies beyond [BigInt](https://github.com/attaswift/BigInt) and [Sparkle](https://sparkle-project.org). To build it from source, see [CONTRIBUTING.md](CONTRIBUTING.md); for how it speaks to the Apple TV, see [docs/how-it-works.md](docs/how-it-works.md).

## License

[MIT](LICENSE)
