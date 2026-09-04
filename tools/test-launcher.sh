#!/usr/bin/env bash
# Off-device test for the launcher's teardown.
#
# The launcher mutates two pieces of SYSTEM-WIDE state for the duration of a
# session -- the CPU governor and PipeWire's forced clock rate/quantum -- so
# failing to undo them leaves the device misconfigured until reboot. That is
# the behaviour this exercises, in a sandbox, on any machine with bash.
#
# It replaces the PortMaster control folder, sysfs governor nodes, weston
# runtime and pw-metadata with stubs, then checks that after each exit path
# the governor is back to its old value and the PipeWire overrides are
# cleared. Run it after touching the launcher.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="$HERE/port/Legend of Zelda - The Minish Cap.sh"
SB="$(mktemp -d)"
trap 'pkill -9 -f "$SB/launcher.sh" 2>/dev/null; pkill -9 -f "$SB/game-sleep" 2>/dev/null; rm -rf "$SB"' EXIT

mkdir -p "$SB"/{bin,PortMaster/libs,weston,state,sys/policy0}
GAMEDIR="$SB/roms/ports/picori"; mkdir -p "$GAMEDIR"

echo powersave > "$SB/sys/policy0/scaling_governor"
echo "ondemand powersave performance schedutil" > "$SB/sys/policy0/scaling_available_governors"

cat > "$SB/bin/pw-metadata" <<EOF
#!/bin/bash
echo "\$*" >> "$SB/state/pw.log"
EOF
printf '#!/bin/bash\nexit 1\n'  > "$SB/bin/pidof"
printf '#!/bin/bash\nexit 0\n'  > "$SB/bin/chrt"
printf '#!/bin/bash\n:\n'       > "$SB/bin/mount"
printf '#!/bin/bash\n:\n'       > "$SB/bin/umount"
chmod +x "$SB/bin/"*

cat > "$SB/PortMaster/control.txt" <<EOF
directory="${SB#/}/roms"
ESUDO=""; GPTOKEYB2="true"; PM_CAN_MOUNT="N"
DEVICE_ARCH="aarch64"; CFW_NAME="muos"; sdl_controllerconfig=""
get_controls() { :; }
pm_message() { echo "\$*" >> "$SB/state/messages.log"; }
pm_finish()  { touch "$SB/state/pm_finish.stamp"; }
EOF
touch "$SB/PortMaster/libs/weston_pkg_0.2.squashfs" "$SB/PortMaster/harbourmaster"

# Redirect the launcher's absolute paths into the sandbox.
sed -e "s#/sys/devices/system/cpu/cpufreq/policy\*#$SB/sys/policy*#g" \
    -e "s#/sys/devices/system/cpu/cpu\[0-9\]\*/cpufreq/scaling_governor#$SB/sys/none/scaling_governor#g" \
    -e "s#weston_dir=\"/tmp/weston\"#weston_dir=\"$SB/weston\"#" \
    -e "s#/sys/class/graphics/fb0#$SB/sys/fb0#g" \
    "$LAUNCHER" > "$SB/launcher.sh"

export PATH="$SB/bin:$PATH" XDG_DATA_HOME="$SB"

stub_weston() { # $1: "runs" (blocks until killed) | "quits"
  # Both variants record the argument vector: the launcher passes the
  # game's environment to westonwrap as VAR=value arguments, so this is
  # where the audio-driver decision becomes observable.
  if [ "$1" = "quits" ]; then
    cat > "$SB/weston/westonwrap.sh" <<EOF
#!/bin/bash
[ "\$1" = "cleanup" ] && exit 0
printf '%s\n' "\$@" > "$SB/state/weston.args"
env > "$SB/state/weston.env"
exit 0
EOF
  else
    cat > "$SB/weston/westonwrap.sh" <<EOF
#!/bin/bash
[ "\$1" = "cleanup" ] && exit 0
printf '%s\n' "\$@" > "$SB/state/weston.args"
env > "$SB/state/weston.env"
trap 'kill \$SP 2>/dev/null; exit 0' TERM INT
exec -a game-sleep sleep 300 & SP=\$!
wait \$SP
EOF
  fi
  chmod +x "$SB/weston/westonwrap.sh"
}

fails=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then printf '  ok    %-22s %s\n' "$1" "$3"
  else printf '  FAIL  %-22s expected %s, got %s\n' "$1" "$2" "$3"; fails=$((fails+1)); fi
}

reset() { rm -f "$SB/state/"* 2>/dev/null; echo powersave > "$SB/sys/policy0/scaling_governor"; }

echo "== no ROM present =="
reset; rm -rf "$GAMEDIR/assets" "$GAMEDIR"/*.gba
bash "$SB/launcher.sh" >/dev/null 2>&1; st=$?
check "exit status"   "1"         "$st"
check "governor"      "powersave" "$(cat "$SB/sys/policy0/scaling_governor")"
check "pipewire calls" "0"        "$(cat "$SB/state/pw.log" 2>/dev/null | wc -l | tr -d ' ')"
check "pm_finish"     "yes"       "$([ -f "$SB/state/pm_finish.stamp" ] && echo yes || echo no)"

mkdir -p "$GAMEDIR/assets"; head -c 1024 /dev/zero > "$GAMEDIR/baserom.gba"

echo "== game exits normally =="
reset; stub_weston quits
bash "$SB/launcher.sh" >/dev/null 2>&1; st=$?
sleep 5   # outlast the 3s governor-pin cycle
check "exit status"   "0"         "$st"
check "governor"      "powersave" "$(cat "$SB/sys/policy0/scaling_governor")"
check "pipewire reset" "2"        "$(grep -c -- '-d$' "$SB/state/pw.log")"
check "pm_finish"     "yes"       "$([ -f "$SB/state/pm_finish.stamp" ] && echo yes || echo no)"

echo "== killed mid-game (SIGTERM, i.e. a crash or muOS reaping the port) =="
reset; stub_weston runs
bash "$SB/launcher.sh" >/dev/null 2>&1 & lp=$!
sleep 4
check "governor pinned" "performance" "$(cat "$SB/sys/policy0/scaling_governor")"
kill -TERM $lp 2>/dev/null
{ ( sleep 25; kill -9 $lp 2>/dev/null ) & wd=$!; } 2>/dev/null
wait $lp 2>/dev/null; st=$?; kill $wd 2>/dev/null; wait $wd 2>/dev/null
sleep 5
check "exit status"   "143"       "$st"
check "governor"      "powersave" "$(cat "$SB/sys/policy0/scaling_governor")"
check "pipewire reset" "2"        "$(grep -c -- '-d$' "$SB/state/pw.log")"
check "pm_finish"     "yes"       "$([ -f "$SB/state/pm_finish.stamp" ] && echo yes || echo no)"
check "game stopped"  "0"         "$(pgrep -f game-sleep | wc -l | tr -d ' ')"

# --------------------------------------------------------------------------
# Device adaptation.
#
# The port is meant to install on more than the RG35XX SP, and the launcher
# is where that portability lives: it picks aspect_mode / internal_scale
# from the panel, writes a weston.ini that is not tied to one output name,
# and only takes the PipeWire path when there is a graph to talk to. None
# of that can be checked on the SP -- the SP is one point of the matrix --
# so it is checked here instead.
# --------------------------------------------------------------------------

fresh_game() {
  rm -rf "$GAMEDIR"
  mkdir -p "$GAMEDIR/assets"
  head -c 1024 /dev/zero > "$GAMEDIR/baserom.gba"
  # The real shipped file, so the seeding is exercised against the exact
  # formatting it has to edit rather than a convenient fake.
  cp "$HERE/port/picori/config.json" "$GAMEDIR/config.json"
  reset
}

cfg_get() { # $1: key -> its value, unquoted
  grep -o "\"$1\": *[^,]*" "$GAMEDIR/config.json" | head -1 | sed 's/.*: *//; s/"//g'
}

launch_at() { # $1: width  $2: height
  DISPLAY_WIDTH="$1" DISPLAY_HEIGHT="$2" bash "$SB/launcher.sh" >/dev/null 2>&1
}

stub_weston quits

echo "== panel -> config seeding =="
# 640x480 is the SP: 4:3, so the deliberate stretch stays, and the panel is
# wide enough for the 2x prescale that makes the 60 FPS cap reachable.
fresh_game; launch_at 640 480
check "640x480 aspect"   "stretch"       "$(cfg_get aspect_mode)"
check "640x480 iscale"   "2"             "$(cfg_get internal_scale)"

# 720x720 (RGB30 / CubeXX). Stretching a 3:2 frame to 1:1 would be grotesque.
fresh_game; launch_at 720 720
check "720x720 aspect"   "pixel_perfect" "$(cfg_get aspect_mode)"
check "720x720 iscale"   "2"             "$(cfg_get internal_scale)"

# 1280x720 (TrimUI Smart Pro class). 16:9, likewise not a stretch target.
fresh_game; launch_at 1280 720
check "1280x720 aspect"  "pixel_perfect" "$(cfg_get aspect_mode)"

# 320x240: 4:3, but too narrow for the 480x320 prescale to be anything but
# wasted bandwidth.
fresh_game; launch_at 320 240
check "320x240 aspect"   "stretch"       "$(cfg_get aspect_mode)"
check "320x240 iscale"   "1"             "$(cfg_get internal_scale)"

# No DISPLAY_WIDTH/HEIGHT (older PortMaster): the SP's own sysfs. Its
# virtual_size is 640,960 (two page-flip buffers), so the mode line must win.
mkdir -p "$SB/sys/fb0"
echo "U:640x480p-59" > "$SB/sys/fb0/modes"; echo "640,960" > "$SB/sys/fb0/virtual_size"
fresh_game; DISPLAY_WIDTH= DISPLAY_HEIGHT= bash "$SB/launcher.sh" >/dev/null 2>&1
check "fb0 fallback aspect" "stretch"    "$(cfg_get aspect_mode)"
check "fb0 fallback iscale" "2"          "$(cfg_get internal_scale)"
rm -f "$SB/sys/fb0/modes"
fresh_game; DISPLAY_WIDTH= DISPLAY_HEIGHT= bash "$SB/launcher.sh" >/dev/null 2>&1
check "virtual_size last resort" "1"     "$(grep -c 'seeded .* for 640x960' "$GAMEDIR/log.txt")"

echo "== seeding is first-launch only =="
# The same file holds the player's own Settings changes, so a second launch
# must not reassert the device defaults over them.
fresh_game; launch_at 640 480
sed -i.bak 's/"internal_scale": 2/"internal_scale": 1/' "$GAMEDIR/config.json"; rm -f "$GAMEDIR/config.json.bak"
launch_at 640 480
check "player value kept" "1"            "$(cfg_get internal_scale)"

echo "== generated weston.ini =="
fresh_game; launch_at 640 480
WINI="$GAMEDIR/runtime/weston.ini"
check "weston.ini written" "yes"         "$([ -s "$WINI" ] && echo yes || echo no)"
check "keeps the SP output" "1"          "$(grep -c '^name=VGA-0$' "$WINI")"
check "names other panels" "yes"         "$(grep -q '^name=HDMI-A-1$' "$WINI" && grep -q '^name=DSI-1$' "$WINI" && echo yes || echo no)"
check "composites 1:1"     "0"           "$(grep -c '^scale=2$' "$WINI")"

echo "== audio: pipewire present =="
fresh_game; launch_at 640 480
check "forces the rate"  "1"             "$(grep -c 'clock.force-rate 44100' "$SB/state/pw.log")"
check "asks for pipewire" "1"            "$(grep -c '^SDL_AUDIODRIVER=pipewire$' "$SB/state/weston.args")"
check "matches the quantum" "1"          "$(grep -c '^SDL_AUDIO_DEVICE_SAMPLE_FRAMES=768$' "$SB/state/weston.args")"

echo "== audio: no pipewire (ArkOS and friends) =="
# Without a graph, naming the pipewire driver would leave the port silent.
# The launcher must pass no driver at all and let SDL probe -- and must not
# leave PW_FORCED set, or cleanup would call a pw-metadata that isn't there.
mv "$SB/bin/pw-metadata" "$SB/bin/pw-metadata.hidden"
fresh_game; launch_at 640 480
check "no driver forced" "0"             "$(grep -c '^SDL_AUDIODRIVER' "$SB/state/weston.args")"
check "no empty driver"  "0"             "$(grep -c '^SDL_AUDIODRIVER=$' "$SB/state/weston.args")"
check "no pw calls"      "0"             "$(cat "$SB/state/pw.log" 2>/dev/null | wc -l | tr -d ' ')"
check "still finishes"   "yes"           "$([ -f "$SB/state/pm_finish.stamp" ] && echo yes || echo no)"
mv "$SB/bin/pw-metadata.hidden" "$SB/bin/pw-metadata"

echo "== sudo-based CFW (ArkOS): ESUDO resets the environment =="
# PortMaster's ESUDO there is `sudo --preserve-env=<short list>`, so anything
# the launcher merely exports does not reach westonwrap or the governor nodes.
# esudo mimics that: it runs its command under a scrubbed environment.
cat > "$SB/bin/esudo" <<EOF2
#!/bin/bash
exec /usr/bin/env -i PATH="\$PATH" HOME="\$HOME" "\$@"
EOF2
chmod +x "$SB/bin/esudo"
sed -i.bak "s#ESUDO=\"\"#ESUDO=\"$SB/bin/esudo\"#" "$SB/PortMaster/control.txt"; rm -f "$SB/PortMaster/control.txt.bak"
fresh_game; stub_weston runs
bash "$SB/launcher.sh" >/dev/null 2>&1 & lp=$!
sleep 4
check "governor pinned via esudo" "performance" "$(cat "$SB/sys/policy0/scaling_governor")"
check "WESTON_CONFIG reaches westonwrap" "$GAMEDIR/runtime/weston.ini" "$(sed -n 's/^WESTON_CONFIG=//p' "$SB/state/weston.env" 2>/dev/null)"
check "PIPEWIRE_RUNTIME_DIR reaches it" "/run" "$(sed -n 's/^PIPEWIRE_RUNTIME_DIR=//p' "$SB/state/weston.env" 2>/dev/null)"
check "controller config as app arg" "1" "$(grep -c "^SDL_GAMECONTROLLERCONFIG='" "$SB/state/weston.args")"
kill -TERM $lp 2>/dev/null; wait $lp 2>/dev/null
sleep 5
check "governor restored"  "powersave" "$(cat "$SB/sys/policy0/scaling_governor")"
check "game stopped"       "0"         "$(pgrep -f game-sleep | wc -l | tr -d ' ')"
sed -i.bak "s#ESUDO=\"$SB/bin/esudo\"#ESUDO=\"\"#" "$SB/PortMaster/control.txt"; rm -f "$SB/PortMaster/control.txt.bak"

echo
if [ "$fails" -eq 0 ]; then echo "all checks passed"; else echo "$fails check(s) FAILED"; fi
exit $((fails > 0))
