#!/bin/bash
# Project Picori (The Legend of Zelda: The Minish Cap) - PortMaster launcher
#
# Binary: github.com/lorencouse/tmc branch rg35xx-sp-audio-ui, a fork of
# 999sian/tmc v0.8.3 adding, for Linux aarch64 handhelds: a LINEAR audio
# resampler (upstream's SINC costs a whole A53 core -> music at half speed),
# a 44.1 kHz synth rate, TMC_UI_SCALE for the ImGui overlay on small screens,
# and an aspect_mode="stretch" for 4:3 panels.
#
# Why it is run this way (see README.md for the full write-up):
# - The RG35XX SP has no working KMS: /dev/dri/card0 opens with ENXIO, the
#   panel is legacy fbdev only. SDL3's kmsdrm driver therefore cannot work,
#   and this binary's only other real video driver is x11. So it runs under
#   the PortMaster weston runtime: weston on its (crusty-faked) DRM backend
#   composites to the panel, and its Xwayland gives SDL3 an X display.
# - gfxmode "system", not crusty_*: the port renders in software, needs no
#   GL, and crusty's SDL loader hooks this binary's exported SDL symbols as
#   if they were SDL2 -> "Could not create SDL Window" + SIGSEGV.
# - picori-weston.ini sets output scale=2: the X screen becomes 320x240, the
#   game renders 1x (240x160) and weston upscales on the GPU. The kernel has
#   no SysV IPC (CONFIG_SYSVIPC unset) so MIT-SHM is unavailable and every
#   frame is copied through the X socket; smaller frames keep that cheap.
# - Governor pinned to performance: muOS leaves ports on powersave (480 MHz
#   of 1512); the software PPU needs the clock.
# - Audio: SDL's pipewire backend against muOS's PipeWire; the synth thread
#   is lifted to SCHED_FIFO because it needs most of a core.
# - Pacing: config.json ships vsync=true, decouple_render=true and a 30 FPS
#   render cap. Measured on this device: full game speed (60 TPS) at ~30 FPS.
#   A 60 cap flaps the port's overload guard (60 TPS / ~12 FPS);
#   decouple_render=false gives ~36 FPS but the game itself slows to 0.6x.
#   Tune under Settings (the hardware MENU button is not routed; open it
#   with the in-game "L" prompt on the file select, or F8 on a keyboard).

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

GAMEDIR="/$directory/ports/picori"
cd "$GAMEDIR" || exit 1

# Keep the previous run's log for diagnostics.
cp -f "$GAMEDIR/log.txt" "$GAMEDIR/log.prev.txt" 2>/dev/null
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

# --- teardown -------------------------------------------------------------
# Everything below that mutates state outside this process registers itself
# here. Two of these are system-wide (the CPU governor and PipeWire's clock
# settings), so leaving them behind on a crash misconfigures the whole
# device until reboot -- hence a trap rather than a tail of commands.
WESTON_MOUNTED=""
GOV_PIN_PID=""
GAME_PID=""
GOV_NODES=()
GOV_PREV=()
PW_FORCED=""
CLEANED=""

cleanup() {
  [ -n "$CLEANED" ] && return
  CLEANED=1
  trap - EXIT INT TERM HUP

  # -9, not -TERM: the loop is normally blocked in `sleep 3`, and bash defers
  # a caught signal until the foreground child returns -- long enough for it
  # to wake and re-assert `performance` after we restored the old governor.
  [ -n "$GOV_PIN_PID" ] && kill -9 "$GOV_PIN_PID" 2>/dev/null
  if [ -n "$GAME_PID" ] && kill -0 "$GAME_PID" 2>/dev/null; then
    $ESUDO kill -TERM "$GAME_PID" 2>/dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "$GAME_PID" 2>/dev/null || break
      sleep 0.5
    done
    $ESUDO kill -KILL "$GAME_PID" 2>/dev/null
  fi
  [ -n "$WESTON_MOUNTED" ] && $ESUDO "$weston_dir/westonwrap.sh" cleanup
  if [ -n "$WESTON_MOUNTED" ] && [[ "$PM_CAN_MOUNT" != "N" ]]; then
    $ESUDO umount "$weston_dir" 2>/dev/null
  fi

  local i
  for i in "${!GOV_NODES[@]}"; do
    [ -n "${GOV_PREV[$i]}" ] && \
      $ESUDO sh -c "echo '${GOV_PREV[$i]}' > '${GOV_NODES[$i]}'" 2>/dev/null
  done

  if [ -n "$PW_FORCED" ]; then
    pw_settings clock.force-rate -d
    pw_settings clock.force-quantum -d
  fi

  $ESUDO kill -9 $(pidof gptokeyb2) 2>/dev/null
  pm_finish
}
trap cleanup EXIT INT TERM HUP

pw_settings() { XDG_RUNTIME_DIR=/run pw-metadata -n settings 0 "$@" >/dev/null 2>&1; }

# --- ROM ------------------------------------------------------------------
# The binary is multi-region: it validates the ROM by SHA-1 itself and picks
# USA/EU/JP data at runtime. Any one of the three filenames will do.
ROM_FILES=("baserom.gba"                                 "baserom_eu.gba"                             "baserom_jp.gba")
ROM_SHA1S=("b4bd50e4131b027c334547b4524e2dbbd4227130"    "cff199b36ff173fb6faf152653d1bccf87c26fb7"   "6c5404a1effb17f481f352181d0f1c61a2765c5d")
ROM_NAMES=("USA"                                         "EU"                                         "JP")

rom_found=""
for i in "${!ROM_FILES[@]}"; do
  if [ -f "$GAMEDIR/${ROM_FILES[$i]}" ]; then
    rom_found="$i"
    break
  fi
done

if [ -z "$rom_found" ]; then
  pm_message "No Minish Cap ROM found."
  pm_message "Put baserom.gba in ports/picori (or baserom_eu.gba / baserom_jp.gba)."
  sleep 15
  exit 1
fi

# The asset cache is built from the ROM on first launch and keyed per region.
# Only verify the ROM when there is no cache yet: that is the launch where a
# bad dump actually manifests, and hashing 16 MB costs a couple of seconds on
# this CPU.
if [ ! -d "$GAMEDIR/assets" ] && command -v sha1sum >/dev/null 2>&1; then
  echo "[launcher] verifying ${ROM_FILES[$rom_found]} (first launch)"
  have="$(sha1sum "$GAMEDIR/${ROM_FILES[$rom_found]}" 2>/dev/null | cut -d' ' -f1)"
  if [ "$have" != "${ROM_SHA1S[$rom_found]}" ]; then
    # Not fatal: the binary does its own SHA-1 check and may know dumps this
    # launcher does not. But an unrecognised hash is nearly always the reason
    # a first launch fails, so say so plainly before handing over.
    pm_message "Warning: ${ROM_FILES[$rom_found]} is not the expected ${ROM_NAMES[$rom_found]} dump."
    echo "[launcher] expected ${ROM_SHA1S[$rom_found]}, got ${have:-<unreadable>}"
    sleep 5
  fi
fi

if [ ! -d "$GAMEDIR/assets" ]; then
  pm_message "First launch: extracting game assets from the ROM."
  pm_message "This takes about 2 minutes. The screen will not move -- please wait."
fi

# Keep saves/config inside the port directory instead of $HOME.
export XDG_DATA_HOME="$GAMEDIR/runtime"
mkdir -p "$XDG_DATA_HOME"

export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

# --- weston runtime -------------------------------------------------------
weston_dir="/tmp/weston"
weston_runtime="weston_pkg_0.2"
$ESUDO mkdir -p "${weston_dir}"
if [ ! -f "$controlfolder/libs/${weston_runtime}.squashfs" ]; then
  if [ ! -f "$controlfolder/harbourmaster" ]; then
    pm_message "This port requires the latest PortMaster to run, please go to https://portmaster.games/ for more info."
    sleep 5
    exit 1
  fi
  $ESUDO $controlfolder/harbourmaster --quiet --no-check runtime_check "${weston_runtime}.squashfs"
fi
if [[ "$PM_CAN_MOUNT" != "N" ]]; then
    $ESUDO umount "${weston_dir}" 2>/dev/null
fi
$ESUDO mount "$controlfolder/libs/${weston_runtime}.squashfs" "${weston_dir}"
WESTON_MOUNTED=1

# --- CPU governor + audio thread priority ---------------------------------
# Pin governors to performance for the session (Dusklight.sh pattern; nodes
# without "performance" are left alone). muOS writes the governor behind a
# running port's back -- frontend.sh's SET_DEFAULT_GOVERNOR when the previous
# launch is reaped, charge.sh on charger events (it hard-codes powersave) --
# and at 480 MHz the game drops to ~8 FPS / 45 TPS. So the pin is re-asserted
# every 3 s until exit.
for g in /sys/devices/system/cpu/cpufreq/policy*/scaling_governor \
         /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do
  [ -f "$g" ] || continue
  avail="${g%/*}/scaling_available_governors"
  if [ -r "$avail" ] && ! grep -qw performance "$avail"; then
    continue
  fi
  prev="$(cat "$g" 2>/dev/null)"
  [ "$prev" = "performance" ] && continue
  GOV_NODES+=("$g")
  GOV_PREV+=("$prev")
done

# The same loop lifts the port's audio thread to SCHED_FIFO once it exists.
# The MP2K synth still takes ~50% of an A53 core with the LINEAR resampler
# (it was ~100% with upstream's SINC), so as SCHED_OTHER it can lose the core
# to the renderer/compositor mid-buffer. muOS runs ports as root, so chrt
# just works (PipeWire itself runs FIFO 88).
(
  audio_tid=""
  while :; do
    for g in "${GOV_NODES[@]}"; do
      [ "$(cat "$g" 2>/dev/null)" = "performance" ] || echo performance > "$g" 2>/dev/null
    done
    if [ -z "$audio_tid" ]; then
      for p in $(pidof tmc_pc); do
        for c in /proc/$p/task/*/comm; do
          case "$(cat "$c" 2>/dev/null)" in
            SDLAudioP*) audio_tid="${c%/comm}"; audio_tid="${audio_tid##*/}"
                        chrt -f -p 60 "$audio_tid" 2>/dev/null && echo "[launcher] audio thread $audio_tid -> SCHED_FIFO 60" ;;
          esac
        done
      done
    fi
    sleep 3
  done
) &
GOV_PIN_PID=$!

# --- input ----------------------------------------------------------------
# All input comes through gptokeyb. weston's libinput refuses muOS-Keys
# outright ("device is a joystick or a gamepad, ignoring") and SDL3 finds no
# gamepad on it either, so the pad has to arrive as a virtual keyboard.
# tmc_pc.gptk mirrors the keyboard half of config.json's "bindings".
$GPTOKEYB2 "tmc_pc" -c "$GAMEDIR/tmc_pc.gptk" &

# Allow an override from picori.env for on-device experimentation without
# re-pushing this script (e.g. TMC_PROFILE=1 TMC_PACE_LOG=1 for the port's
# own per-frame timings).
[ -f "$GAMEDIR/picori.env" ] && source "$GAMEDIR/picori.env"

echo "--- picori launch $(date) ---"
echo "DEVICE_ARCH=${DEVICE_ARCH} CFW_NAME=${CFW_NAME} weston=drm/gl/kiosk gfx=system"
echo "ROM=${ROM_FILES[$rom_found]} (${ROM_NAMES[$rom_found]})"

# --- audio ----------------------------------------------------------------
# 44.1 kHz, not 48: this codec's "48000" clock runs measurably fast (music
# tempo up, dropout every 1-2 s as the DAC outruns its feed); at 44.1 kHz
# it is honest -- which is presumably why muOS defaults to it.
# 768, not 1024: muOS opens the codec with api.alsa.period-size=192 x 8 =
# a 1536-frame buffer, so PipeWire's real cycle is at most 768 frames
# (57.4 cycles/s at 44.1 kHz). SDL 3.4 fills its device buffer once per
# cycle regardless of what the cycle asks for; with its default 1024 that
# is 1.33x real time, the surplus gets dropped, and the music ran 9% fast
# with a seam every few cycles. Matching both to 768 makes SDL's pull
# exactly the DAC's consumption (measured 44 544 vs 44 101 frames/s).
# These are runtime metadata on the system graph, cleared again by cleanup().
PW_FORCED=1
pw_settings clock.force-rate 44100
pw_settings clock.force-quantum 768

# OMP_WAIT_POLICY=passive: the port's OpenMP scanline workers otherwise
# spin-wait at their barrier and fight the audio thread for the 4 cores.
# SDL_AUDIODRIVER=pipewire: SDL talks to muOS's PipeWire directly. The ALSA
# route (asound.conf -> pipewire ALSA plugin) underran ~180x/s here.
# PIPEWIRE_RUNTIME_DIR is spelled out because westonwrap resets
# XDG_RUNTIME_DIR (an early run SIGSEGV'd inside libpipewire without it).
export PIPEWIRE_RUNTIME_DIR=/run
export WESTON_CONFIG="$GAMEDIR/picori-weston.ini"
$ESUDO $weston_dir/westonwrap.sh drm gl kiosk system \
SDL_VIDEODRIVER=x11 \
SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-pipewire}" \
SDL_AUDIO_DEVICE_SAMPLE_FRAMES="${SDL_AUDIO_DEVICE_SAMPLE_FRAMES:-768}" \
PIPEWIRE_RUNTIME_DIR=/run \
OMP_WAIT_POLICY=passive \
XDG_DATA_HOME="$XDG_DATA_HOME" \
SDL_GAMECONTROLLERCONFIG="$SDL_GAMECONTROLLERCONFIG" \
./tmc_pc &
GAME_PID=$!

# Do not foreground the game: see cleanup() above.
wait "$GAME_PID"
status=$?
GAME_PID=""

cleanup
exit "$status"
