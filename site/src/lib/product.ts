// What Clicker is and does, in plain text, for every place that describes it to
// a reader or a machine: the homepage's feature list, the meta description,
// the JSON-LD and /llms.txt. Keep each fact in line with the README.

export const site = "https://clicker.jarv.is";
export const repo = "https://github.com/jakejarvis/Clicker";
export const brewCommand = "brew install --cask jakejarvis/tap/clicker";

export const summary =
  "Clicker is a free, open-source Apple TV remote for the Mac. It lives in the menu bar and gives you the Siri Remote's buttons, swipes, Siri, volume, app launching, power controls and typing with your Mac's keyboard.";

export const description =
  "A free, open-source Apple TV remote for your Mac's menu bar: clickpad, swipes, Siri, volume, apps, power and typing with your keyboard. No account needed.";

export const requirements = "macOS 15 or later, on an Apple silicon or Intel Mac.";

export interface Feature {
  title: string;
  text: string;
}

export const features: Feature[] = [
  {
    title: "Every Siri Remote button",
    text: "A clickpad to move and select, plus Back, TV, Play/Pause, Siri, volume and mute.",
  },
  {
    title: "Swipe with your trackpad",
    text: "Scroll with two fingers over the clickpad to swipe, like the Siri Remote's touch surface.",
  },
  {
    title: "Type with your keyboard",
    text: "When a search box or password field is on the TV, type into it from your Mac.",
  },
  {
    title: "Keyboard shortcuts",
    text: "Arrow keys, Return, Space and more drive the TV, and a shortcut of your choice opens the remote from any app.",
  },
  {
    title: "Launch apps",
    text: "Search your Apple TV's apps and open one, with favorites pinned to the top.",
  },
  {
    title: "Power and more",
    text: "Wake, Sleep, Screen Saver, Control Center and Guide, and switch between Apple TVs in a click.",
  },
  {
    title: "Private by design",
    text: "Talks to the Apple TV directly over your network, with no account, cloud service, helper app or analytics.",
  },
  {
    title: "Native and tiny",
    text: "A SwiftUI menu bar app with no Dock icon, signed and notarized by Apple, that keeps itself up to date.",
  },
];
