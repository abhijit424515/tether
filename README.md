# Tether

Keeps your Mac's audio tied to the devices you actually want.

macOS forgets which microphone you picked the moment a Bluetooth headset reconnects. Tether puts it back.

You give it a priority order per direction — input and output — and it keeps the system on the highest-priority device that is currently connected. Unplug the headset, it falls to the next one down. Plug it back in, it returns.

The motivating case: a cheap headset with a bad mic. You want its speakers, but you want the MacBook's microphone. macOS drops that pairing on every reconnect.

Two ways to run it: a **menu bar app** (no terminal, no dependencies) or a **CLI + background agent**. They share one config file, so you can use either. Do not run both at once — they would both be switching devices.

## Menu bar app

```sh
brew install --cask abhijit424515/dynamight/tether
```

Tether is ad-hoc signed rather than notarized by Apple, so the cask clears the quarantine attribute that Homebrew sets on downloads — Gatekeeper only inspects quarantined files, and would otherwise refuse to launch it. That means you are trusting this source instead of Apple's notary service. Everything here is buildable from source if you would rather not:

```sh
git clone https://github.com/abhijit424515/tether.git
cd tether && ./app/install.sh
```

That builds Tether and copies it to `/Applications` (or `~/Applications` if that needs an admin you do not have), then launches it. Installing matters for more than tidiness: Spotlight, Raycast and Launchpad do not index build directories, so an app left in `app/build` cannot be found by name. Use `./app/build.sh` alone if you only want to compile.

Tether's waveform icon appears in the menu bar, in monochrome — it is a template image, so macOS recolors it for light, dark and highlighted menu bars. The blue gradient original is used for the app icon in Finder, the Dock and Raycast.

Click it and a small panel drops down with two tabs, **Microphone** and **Speakers**. Each tab is a numbered list of every device it has seen; drag the rows to set the order you want. The topmost device that is currently connected is the one macOS uses, and it stays that way across disconnects.

Rows show `in use` for the active device and `not connected` for one that is unplugged — unplugged devices stay in the list so you can position them ahead of time. Right-click one to forget it. Turn on **Open at Login** so it starts with your Mac.

A volume slider under the tabs controls whichever device is active in that tab; it is disabled for devices that expose no volume control, such as HDMI outputs and many USB microphones. The Microphone tab also shows a live input level meter.

The meter is the only part of Tether that opens the microphone, so it runs only while the Microphone tab is on screen — not on the Speakers tab, and not while the panel is closed. macOS asks for microphone permission the first time. Because the build is ad-hoc signed, its signature changes on every rebuild, so macOS may ask again after each `install.sh`.

No Dock icon, no window. It talks to CoreAudio directly — no Homebrew, no `switchaudio-osx`. Requires macOS 13 or later.

The build is ad-hoc signed, so on another Mac the first launch needs right-click → Open to get past Gatekeeper.

## CLI

```sh
brew install switchaudio-osx
git clone https://github.com/abhijit424515/tether.git
cd tether
ln -s "$PWD/tether" /opt/homebrew/bin/tether
```

Then install the launch agent (edit the path if you cloned elsewhere):

```sh
sed "s|PLACEHOLDER|$PWD/tether-agent.sh|" com.local.tether.plist \
  > ~/Library/LaunchAgents/com.local.tether.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.local.tether.plist
```

## Use

```sh
tether
```

Opens `~/.config/tether.json` in `$EDITOR` (nvim by default), creating it from your connected devices on first run. Save and quit; it validates the JSON, re-prompts if you broke something, and reloads the agent.

```json
{
  "input": ["MacBook Pro Microphone", "Rockerz 255 ANC"],
  "output": ["Rockerz 255 ANC", "XV272U F3", "MacBook Pro Speakers"]
}
```

First entry wins when connected. Names must match `SwitchAudioSource -a -t input` exactly; `tether` warns about entries it does not currently see, but does not reject them — a device you own but have unplugged is a valid entry.

Both the app and the CLI move an older `~/.config/audio-priority.json` to the new name on first run.

## Files

| File | Role |
| --- | --- |
| `app/Tether.swift` | The whole menu bar app. CoreAudio enumeration and switching, panel, login item. |
| `app/Reorder.swift` | Drag-reorder index and gesture math, kept pure so it can be tested. |
| `app/InputMeter.swift` | Live microphone level: the audio tap, the smoothing, and the meter view. |
| `app/build.sh` | `swiftc` + a hand-made `.app` bundle. No Xcode project. |
| `app/install.sh` | Builds, then copies the bundle to `/Applications` so Spotlight and Raycast can find it. |
| `app/release.sh` | Stamps a version, zips the bundle, publishes a GitHub release, prints the cask sha256. |
| `app/icon.svg` | Source artwork, blue gradient. `icon-app.svg` and `icon-menubar.svg` are crops of it. |
| `app/make-icon.sh` | Renders both icons from the SVGs (needs `librsvg`). Output is committed. |
| `tether` | CLI: edit, validate, apply. |
| `tether-agent.sh` | The agent. Polls every 2s, switches when the current device is not the best available. |
| `com.local.tether.plist` | launchd template that keeps the agent running and restarts it at login. |
| `test.sh`, `app/test.sh` | Self-checks for the shell agent and the reorder logic. |

## Managing the agent

```sh
launchctl kickstart -k gui/$(id -u)/com.local.tether   # restart
launchctl bootout   gui/$(id -u)/com.local.tether      # stop
cat /tmp/tether.err                                    # errors
```

## Notes

Polling, not a CoreAudio event listener — a 2s reaction is not worth the extra machinery. Config is re-read every pass, so edits apply without a restart. `jq` ships with macOS; the CLI's only dependency is `switchaudio-osx`, and the app has none.

Reordering in the app uses a `DragGesture` rather than drag-and-drop: a `MenuBarExtra` popover is a non-activating panel, so `NSDraggingSession` never starts inside it and both `List`'s `.onMove` and `.draggable` silently do nothing.
