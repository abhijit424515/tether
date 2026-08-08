#!/bin/bash
# Keeps audio in/out on the highest-priority device that is currently connected.
# Config: ~/.config/audio-priority.json  ->  {"input": ["Name", ...], "output": ["Name", ...]}
# ponytail: polls every 2s instead of a CoreAudio listener. Swap in a Swift listener only if 2s lag annoys.

SAS=/opt/homebrew/bin/SwitchAudioSource
CONF="${AUDIO_PRIORITY_CONF:-$HOME/.config/audio-priority.json}"

pick() {
  local type=$1 wanted available current
  # bad/missing config: warn once per pass, change nothing
  wanted=$(jq -er --arg t "$type" '.[$t][]? | select(type == "string")' "$CONF" 2>&1) || {
    echo "audio-priority: cannot read $type priorities from $CONF: $wanted" >&2
    return
  }
  available=$("$SAS" -a -t "$type")
  current=$("$SAS" -c -t "$type")
  while IFS= read -r want; do
    [ -z "$want" ] && continue
    grep -qxF "$want" <<<"$available" || continue
    [ "$want" = "$current" ] || "$SAS" -t "$type" -s "$want"
    return
  done <<<"$wanted"
}

[ "$1" = "--once" ] && { pick input; pick output; exit 0; }

while true; do
  pick input
  pick output
  sleep 2
done
