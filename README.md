# Tether

Keeps your Mac's audio on the devices you actually want.

macOS forgets which microphone you picked the moment a Bluetooth headset reconnects. Tether puts it back. You set a priority order for inputs and outputs, and it keeps the system on the highest-priority device that is currently connected.

The case it was built for: a cheap headset with a bad mic. You want its speakers, but the MacBook's microphone — and macOS drops that pairing every time the headset reconnects.

## Install

```sh
brew install --cask abhijit424515/dynamight/tether
```

Requires macOS 13 or later. Tether is ad-hoc signed rather than notarized by Apple, so the cask clears the quarantine attribute that would otherwise stop it launching — you are trusting this source instead of Apple's notary service. Build it yourself if you would rather not:

```sh
git clone https://github.com/abhijit424515/tether.git
cd tether && ./app/install.sh
```

## Use

Click the waveform icon in the menu bar.

- **Two tabs**, Microphone and Speakers. Each lists every device Tether has seen, numbered by priority.
- **Drag rows** to reorder. The topmost connected device wins, and stays winning across disconnects.
- **Volume slider** for whichever device is active in that tab. Greyed out for devices with no volume control, like HDMI outputs.
- **Input level meter** on the Microphone tab. macOS asks for microphone permission the first time — nothing is recorded, and the mic is opened only while that tab is on screen.
- **Right-click a device** to forget it. Disconnected devices stay listed so you can position them before plugging in.
- **Open at Login** starts Tether with your Mac.

Priorities live in `~/.config/tether.json`, which you can edit by hand — it is re-read every couple of seconds.

```json
{
  "input": ["MacBook Pro Microphone", "Rockerz 255 ANC"],
  "output": ["Rockerz 255 ANC", "MacBook Pro Speakers"]
}
```

## Without the app

There is also a CLI and a launchd agent doing the same job, if you prefer no GUI. It needs `brew install switchaudio-osx`, and shares the same config file. Run one or the other, not both.

```sh
ln -s "$PWD/tether" /opt/homebrew/bin/tether
sed "s|PLACEHOLDER|$PWD/tether-agent.sh|" com.local.tether.plist \
  > ~/Library/LaunchAgents/com.local.tether.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.local.tether.plist
```

`tether` opens the config in `$EDITOR`, validates it, and reloads the agent.

## Development

Plain `swiftc`, no Xcode project. Contributions welcome.

```sh
./app/build.sh      # compile into app/build/Tether.app
./app/install.sh    # build and install to /Applications
./app/test.sh       # reorder logic
./test.sh           # shell agent
./app/make-icon.sh  # re-render icons from the SVGs (needs librsvg)
./app/release.sh 1.1.0
```

Releasing also means bumping `version` and `sha256` in [the tap](https://github.com/abhijit424515/homebrew-dynamight).
