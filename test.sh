#!/bin/bash
# Self-check for pick(): fakes SwitchAudioSource, asserts the chosen device.
set -e
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/SwitchAudioSource" <<'EOF'
#!/bin/bash
[ "$1" = "-a" ] && { cat "$FAKE_AVAILABLE"; exit; }
[ "$1" = "-c" ] && { echo "$FAKE_CURRENT"; exit; }
echo "$4" > "$FAKE_SWITCHED"
EOF
chmod +x "$TMP/SwitchAudioSource"

sed "s|^SAS=.*|SAS=$TMP/SwitchAudioSource|" "$(dirname "$0")/audio-priority.sh" > "$TMP/run.sh"
chmod +x "$TMP/run.sh"

export FAKE_AVAILABLE="$TMP/avail" FAKE_SWITCHED="$TMP/switched"
export AUDIO_PRIORITY_CONF="$TMP/conf.json"

check() { # desc, expected ("" = no switch)
  [ "$(cat "$TMP/switched" 2>/dev/null)" = "$2" ] && echo "ok: $1" && return
  echo "FAIL: $1 — wanted '$2', got '$(cat "$TMP/switched" 2>/dev/null)'"; exit 1
}

echo '{"input":["Good Mic","Cheap Mic"],"output":["Cheap Mic"]}' >"$AUDIO_PRIORITY_CONF"

printf 'Good Mic\nCheap Mic\n' >"$TMP/avail"; FAKE_CURRENT="Cheap Mic" "$TMP/run.sh" --once
check "top choice present -> switches" "Good Mic"

rm -f "$TMP/switched"
printf 'Cheap Mic\n' >"$TMP/avail"; FAKE_CURRENT="Cheap Mic" "$TMP/run.sh" --once
check "top choice absent, fallback already current -> no switch" ""

rm -f "$TMP/switched"
printf 'Unlisted\n' >"$TMP/avail"; FAKE_CURRENT="Unlisted" "$TMP/run.sh" --once
check "nothing listed is connected -> no switch" ""

rm -f "$TMP/switched"
echo 'not json' >"$AUDIO_PRIORITY_CONF"
printf 'Good Mic\n' >"$TMP/avail"; FAKE_CURRENT="Cheap Mic" "$TMP/run.sh" --once
check "broken config -> no switch, no crash" ""

PAI="$(dirname "$0")/pai"
vcheck() { # desc, json, expected exit
  echo "$2" >"$TMP/v.json"
  local got=0
  "$PAI" --check "$TMP/v.json" 2>/dev/null || got=$?
  [ "$got" = "$3" ] && echo "ok: $1" && return
  echo "FAIL: $1 — wanted exit $3, got $got"; exit 1
}

vcheck "well-formed config"        '{"input":["A"],"output":["B","C"]}' 0
vcheck "empty arrays are fine"     '{"input":[],"output":[]}'           0
vcheck "extra keys are fine"       '{"input":[],"output":[],"x":1}'     0
vcheck "malformed JSON"            'not json'                           1
vcheck "missing output key"        '{"input":["A"]}'                    1
vcheck "top level is an array"     '["A"]'                              1
vcheck "output is not an array"    '{"input":[],"output":"B"}'          1
vcheck "non-string entry"          '{"input":[1],"output":[]}'          1
vcheck "empty-string entry"        '{"input":[""],"output":[]}'         1

echo "all passed"
