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
    "$LAUNCHER" > "$SB/launcher.sh"

export PATH="$SB/bin:$PATH" XDG_DATA_HOME="$SB"

stub_weston() { # $1: "runs" (blocks until killed) | "quits"
  if [ "$1" = "quits" ]; then
    printf '#!/bin/bash\n[ "$1" = cleanup ] && exit 0\nexit 0\n' > "$SB/weston/westonwrap.sh"
  else
    cat > "$SB/weston/westonwrap.sh" <<EOF
#!/bin/bash
[ "\$1" = "cleanup" ] && exit 0
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

echo
if [ "$fails" -eq 0 ]; then echo "all checks passed"; else echo "$fails check(s) FAILED"; fi
exit $((fails > 0))
