# persistent-audio-io

macOS forgets which microphone you picked the moment a Bluetooth headset reconnects. This puts it back.

You give it a priority order per direction — input and output — and a background agent keeps the system on the highest-priority device that is currently connected. Unplug the headset, it falls to the next one down. Plug it back in, it returns.

The motivating case: a cheap headset with a bad mic. You want its speakers, but you want the MacBook's microphone. macOS drops that pairing on every reconnect.

## Install

```sh
brew install switchaudio-osx
git clone https://github.com/abhijit424515/persistent-audio-io.git
cd persistent-audio-io
ln -s "$PWD/pai" /opt/homebrew/bin/pai
```

Then install the launch agent (edit the path if you cloned elsewhere):

```sh
sed "s|PLACEHOLDER|$PWD/audio-priority.sh|" com.local.audio-priority.plist \
  > ~/Library/LaunchAgents/com.local.audio-priority.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.local.audio-priority.plist
```

## Use

```sh
pai
```

Opens `~/.config/audio-priority.json` in `$EDITOR` (nvim by default), creating it from your connected devices on first run. Save and quit; it validates the JSON, re-prompts if you broke something, and reloads the agent.

```json
{
  "input": ["MacBook Pro Microphone", "Rockerz 255 ANC"],
  "output": ["Rockerz 255 ANC", "XV272U F3", "MacBook Pro Speakers"]
}
```

First entry wins when connected. Names must match `SwitchAudioSource -a -t input` exactly; `pai` warns about entries it does not currently see, but does not reject them — a device you own but have unplugged is a valid entry.

## Files

| File | Role |
| --- | --- |
| `pai` | Edit, validate, apply. The only command you run. |
| `audio-priority.sh` | The agent. Polls every 2s, switches when the current device is not the best available. |
| `com.local.audio-priority.plist` | launchd template that keeps the agent running and restarts it at login. |
| `test.sh` | Self-check. Fakes `SwitchAudioSource`, asserts switch decisions and config validation. |

## Managing the agent

```sh
launchctl kickstart -k gui/$(id -u)/com.local.audio-priority   # restart
launchctl bootout   gui/$(id -u)/com.local.audio-priority      # stop
cat /tmp/audio-priority.err                                    # errors
```

## Notes

Polling, not a CoreAudio event listener — a 2s reaction is not worth a compiled Swift daemon. Config is re-read every pass, so edits apply without a restart. `jq` ships with macOS; the only dependency is `switchaudio-osx`.
