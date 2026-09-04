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
# - weston output scale=1: the X screen matches the panel, so weston
#   composites 1:1 and filters nothing. (scale=2 gave a 320x240 X screen
#   that weston bilinear-upscaled -- cheaper per frame, but it blurred
#   every pixel. config.json's internal_scale=2 buys the speed back
#   instead.) The kernel has no SysV IPC (CONFIG_SYSVIPC unset) so MIT-SHM
#   is unavailable and every frame is copied through the X socket.
#   The weston.ini is generated per launch rather than shipped, because the
#   [output] name differs per device; picori-weston.ini remains as the SP's
#   documented reference and as the fallback if generation fails.
# - Governor pinned to performance: muOS leaves ports on powersave (480 MHz
#   of 1512); the software PPU needs the clock.
# - Audio: SDL's pipewire backend against muOS's PipeWire, but only where a
#   PipeWire graph actually answers -- on a CFW without one the driver is
#   left to SDL's own probe. The synth thread is lifted to SCHED_FIFO
#   because it needs most of a core.
# - Panel-dependent settings (aspect_mode, internal_scale) are seeded from
#   the detected resolution on the FIRST launch only; after that the file
#   belongs to the player. See README.md "Device support".
# - Pacing: config.json ships vsync=true, decouple_render=true, a 60 FPS
#   render grid (frame_time_ns=16666667) and internal_scale=2. Measured on
#   this device: a locked 60 TPS / 60 FPS. The internal_scale is what makes
#   the 60 cap viable -- prescaling 240x160 -> 480x320 in the port's own loop
#   takes SDL's software present from ~16.5 ms to ~8.7 ms, which is what
#   fits inside the 16.67 ms tick window. Raising the cap without it lands
#   at ~14 FPS, not 60. See README.md "Frame rate" before changing either.
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

  # The game has to die before weston does. GAME_PID is westonwrap.sh, not
  # tmc_pc: signalling the wrapper tears down weston -- and with it Xwayland
  # -- while the game is still attached to the display, so libX11's default
  # IO error handler runs inside tmc_pc and glibc aborts partway through its
  # exit path ("free(): corrupted unsorted chunks"). Every quit then landed
  # as a SIGABRT and wrote a ~900 KB bugreport_* bundle into the port dir.
  # So: reap tmc_pc first, wait for it to actually be gone, then the wrapper.
  local gpids
  gpids="$(pidof tmc_pc 2>/dev/null)"
  if [ -n "$gpids" ]; then
    $ESUDO kill -TERM $gpids 2>/dev/null
    for _ in {1..20}; do
      pidof tmc_pc >/dev/null 2>&1 || break
      sleep 0.25
    done
    gpids="$(pidof tmc_pc 2>/dev/null)"
    [ -n "$gpids" ] && $ESUDO kill -KILL $gpids 2>/dev/null
  fi

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
    # weston's children are still exiting when westonwrap cleanup returns, so
    # the first umount can lose the race (seen on the SP: EBUSY once, clean a
    # moment later). A few retries; the next launch umounts again anyway.
    for _ in 1 2 3 4; do
      $ESUDO umount "$weston_dir" 2>/dev/null && break
      sleep 0.5
    done
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

# --- weston runtime -------------------------------------------------------
# Done before anything that talks to the player: the squashfs may have to be
# downloaded (55 MB), and that must not happen after "please wait 2 minutes"
# has already been shown. XDG_DATA_HOME is still the system one here on
# purpose -- harbourmaster is a PortMaster tool and gets PortMaster's paths.
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

# --- panel ----------------------------------------------------------------
# Everything below that depends on the screen derives from these two.
# Current PortMaster builds export DISPLAY_WIDTH/DISPLAY_HEIGHT from
# control.txt, older ones do not, and this port has to cope with both --
# so fall back to the framebuffer's own mode line (fb0/modes reads
# "U:640x480p-59"), then to fb0/virtual_size -- which on the SP is "640,960"
# because it counts the second page-flip buffer, so it is only a last resort
# -- and finally to the RG35XX SP's panel, which is what every measured
# number in README.md was taken on.
screen_is_num() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

SCREEN_W="${DISPLAY_WIDTH:-}"
SCREEN_H="${DISPLAY_HEIGHT:-}"
if ! screen_is_num "$SCREEN_W" || ! screen_is_num "$SCREEN_H"; then
  if [ -r /sys/class/graphics/fb0/modes ]; then
    # "U:640x480p-59" -> 640 480
    fb_mode="$(head -n1 /sys/class/graphics/fb0/modes 2>/dev/null)"
    fb_mode="${fb_mode#*:}"; fb_mode="${fb_mode%%p*}"; fb_mode="${fb_mode%%i*}"
    SCREEN_W="${fb_mode%%x*}"; SCREEN_H="${fb_mode#*x}"
  fi
fi
if ! screen_is_num "$SCREEN_W" || ! screen_is_num "$SCREEN_H"; then
  if [ -r /sys/class/graphics/fb0/virtual_size ]; then
    IFS=, read -r SCREEN_W SCREEN_H < /sys/class/graphics/fb0/virtual_size
    SCREEN_W="$(printf '%s' "$SCREEN_W" | tr -dc '0-9')"
    SCREEN_H="$(printf '%s' "$SCREEN_H" | tr -dc '0-9')"
  fi
fi
if ! screen_is_num "$SCREEN_W" || ! screen_is_num "$SCREEN_H" \
   || [ "$SCREEN_W" -eq 0 ] || [ "$SCREEN_H" -eq 0 ]; then
  SCREEN_W=640; SCREEN_H=480
fi

# --- device-tuned defaults (first launch only) ----------------------------
# config.json ships tuned for the SP: a 4:3 640x480 panel, where "stretch"
# fills it and internal_scale=2 is what makes the 60 FPS cap viable (see
# README.md "Frame rate"). Neither is right on every panel:
#
#   - "stretch" maps the native 3:2 frame onto the whole panel. That is a
#     mild, deliberate distortion on a 4:3 screen. On a 1:1 (RGB30-class)
#     or 16:9 panel it is a gross one, so those get "pixel_perfect"
#     instead -- integer scaling, letterboxed, every game pixel an
#     identical NxN block.
#   - internal_scale=2 prescales 240x160 -> 480x320 in the port's own loop
#     before SDL's software scaler runs. It pays for itself when the
#     window is much bigger than 480x320 and just costs bandwidth when it
#     is not, so it is only seeded on panels at least that wide.
#
# Seeded ONCE and then never touched again: config.json is also where the
# player's own Settings changes are saved, so re-asserting these on every
# launch would silently undo them. Delete runtime/.device-tuned to re-seed.
if [ ! -f "$GAMEDIR/runtime/.device-tuned" ]; then
  seed_aspect="pixel_perfect"
  # Integer thousandths, so no shell float math: 4:3 is 1333.
  seed_ar=$(( SCREEN_W * 1000 / SCREEN_H ))
  if [ "$seed_ar" -ge 1280 ] && [ "$seed_ar" -le 1400 ]; then
    seed_aspect="stretch"
  fi
  seed_iscale=1
  [ "$SCREEN_W" -ge 480 ] && seed_iscale=2

  # A temp file + mv rather than `sed -i`: busybox sed (some CFW ship it
  # as the only sed) rejects the suffix form GNU and BSD spell differently.
  if [ -f "$GAMEDIR/config.json" ]; then
    seed_tmp="$GAMEDIR/config.json.seed.$$"
    if sed -e "s/\"aspect_mode\": \"[a-z_]*\"/\"aspect_mode\": \"$seed_aspect\"/" \
           -e "s/\"internal_scale\": [0-9][0-9]*/\"internal_scale\": $seed_iscale/" \
           "$GAMEDIR/config.json" > "$seed_tmp" 2>/dev/null && [ -s "$seed_tmp" ]; then
      mv -f "$seed_tmp" "$GAMEDIR/config.json"
      echo "[launcher] first launch: seeded aspect_mode=$seed_aspect internal_scale=$seed_iscale for ${SCREEN_W}x${SCREEN_H}"
    else
      rm -f "$seed_tmp"
      echo "[launcher] could not seed config.json -- shipped defaults kept"
    fi
  fi
  mkdir -p "$GAMEDIR/runtime" && touch "$GAMEDIR/runtime/.device-tuned"
fi

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
# to the renderer/compositor mid-buffer. muOS runs ports as root; where they
# are not (ArkOS), $ESUDO supplies the privilege (PipeWire itself runs FIFO 88).
(
  audio_tid=""
  while :; do
    for g in "${GOV_NODES[@]}"; do
      # Through $ESUDO: on ArkOS-class CFWs the launcher is not root and a
      # bare redirect fails silently, leaving the game unpinned.
      [ "$(cat "$g" 2>/dev/null)" = "performance" ] || $ESUDO sh -c "echo performance > '$g'" 2>/dev/null
    done
    if [ -z "$audio_tid" ]; then
      for p in $(pidof tmc_pc); do
        for c in /proc/$p/task/*/comm; do
          case "$(cat "$c" 2>/dev/null)" in
            SDLAudioP*) audio_tid="${c%/comm}"; audio_tid="${audio_tid##*/}"
                        $ESUDO chrt -f -p 60 "$audio_tid" 2>/dev/null && echo "[launcher] audio thread $audio_tid -> SCHED_FIFO 60" ;;
          esac
        done
      done
    fi
    sleep 3
  done
) &
GOV_PIN_PID=$!
# disown: otherwise bash reports the kill -9 in cleanup() as "Killed" in the
# log, which every tester reads as a crash.
disown $GOV_PIN_PID

# --- input ----------------------------------------------------------------
# All input comes through gptokeyb. weston's libinput refuses muOS-Keys
# outright ("device is a joystick or a gamepad, ignoring") and SDL3 finds no
# gamepad on it either, so the pad has to arrive as a virtual keyboard.
# tmc_pc.gptk mirrors the keyboard half of config.json's "bindings".
# -H back nominates SELECT as gptokeyb's hotkey, which activates the
# [controls:hk_hotkey] layer in tmc_pc.gptk while it is held. That layer is
# the only source of spare keys on this device: SDL sees no gamepad here (the
# pad arrives as a virtual keyboard), so the port's own Controls tab can bind
# keys but every key the SP can send is already gameplay. Held SELECT frees
# four of them for the save-state actions.
$GPTOKEYB2 "tmc_pc" -H back -c "$GAMEDIR/tmc_pc.gptk" &
disown $!

# Allow an override from picori.env for on-device experimentation without
# re-pushing this script (e.g. TMC_PROFILE=1 TMC_PACE_LOG=1 for the port's
# own per-frame timings).
[ -f "$GAMEDIR/picori.env" ] && source "$GAMEDIR/picori.env"

echo "--- picori launch $(date) ---"
echo "[launcher] package version $(cat "$GAMEDIR/version.txt" 2>/dev/null || echo unknown)"
echo "DEVICE_ARCH=${DEVICE_ARCH} CFW_NAME=${CFW_NAME} DEVICE_NAME=${DEVICE_NAME:-?} panel=${SCREEN_W}x${SCREEN_H} ESUDO=${ESUDO:-none} weston=drm/gl/kiosk gfx=system"
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
# Both of those numbers are measured against THIS codec on a CFW that
# runs PipeWire. Elsewhere the graph may not exist at all -- ArkOS and
# friends run bare ALSA or PulseAudio, where pw-metadata is absent and
# asking SDL for the pipewire driver by name means it opens no device and
# the port is silent. So probe for a live graph and only take this path
# when there is one; otherwise say nothing and let SDL's own probe pick,
# which is what every other PortMaster title does.
AUDIO_DRIVER="${SDL_AUDIODRIVER:-}"
AUDIO_FRAMES="${SDL_AUDIO_DEVICE_SAMPLE_FRAMES:-}"
if command -v pw-metadata >/dev/null 2>&1 && pw_settings; then
  PW_FORCED=1
  pw_settings clock.force-rate 44100
  pw_settings clock.force-quantum 768
  AUDIO_DRIVER="${AUDIO_DRIVER:-pipewire}"
  AUDIO_FRAMES="${AUDIO_FRAMES:-768}"
  echo "[launcher] pipewire graph found: forced 44100 Hz / 768-frame quantum"
else
  echo "[launcher] no pipewire graph -- leaving the audio driver to SDL"
fi

# Passed through to westonwrap as VAR=value arguments, and only when set:
# SDL treats an empty SDL_AUDIODRIVER as a driver named "", not as unset.
AUDIO_ENV=()
[ -n "$AUDIO_DRIVER" ] && AUDIO_ENV+=("SDL_AUDIODRIVER=$AUDIO_DRIVER")
[ -n "$AUDIO_FRAMES" ] && AUDIO_ENV+=("SDL_AUDIO_DEVICE_SAMPLE_FRAMES=$AUDIO_FRAMES")

# OMP_WAIT_POLICY=passive: the port's OpenMP scanline workers otherwise
# spin-wait at their barrier and fight the audio thread for the 4 cores.
# SDL_AUDIODRIVER=pipewire: SDL talks to muOS's PipeWire directly. The ALSA
# route (asound.conf -> pipewire ALSA plugin) underran ~180x/s here.
# PIPEWIRE_RUNTIME_DIR is spelled out because westonwrap resets
# XDG_RUNTIME_DIR (an early run SIGSEGV'd inside libpipewire without it).
# Exported once here; westonwrap passes its environment through to the game.
export PIPEWIRE_RUNTIME_DIR=/run
# picori-weston.ini documents the SP's settings but names that device's
# output (VGA-0). weston silently ignores an [output] section matching no
# real output, so on a handheld that calls its panel something else the
# whole section would be inert. Generate the file instead and repeat the
# same block under every name these devices are known to use: at most one
# can match and the others cost nothing.
#
# scale=1 on all of them, which is also weston's default -- the X screen
# then matches the panel and weston composites 1:1, filtering nothing.
# scale=2 is cheaper per frame but bilinear-upscales every pixel; that was
# measured on the panel and rejected (README.md "Picture quality").
WESTON_INI="$GAMEDIR/runtime/weston.ini"
mkdir -p "$GAMEDIR/runtime"
if {
  echo "# Generated by the launcher for a ${SCREEN_W}x${SCREEN_H} panel."
  echo "# Edits here are overwritten on the next launch; change"
  echo "# picori-weston.ini instead, or set WESTON_CONFIG in picori.env."
  echo
  echo "[core]"
  echo
  for wout in VGA-0 HDMI-A-1 HDMI-A-2 DSI-1 DSI-2 DPI-1 LVDS-1 eDP-1 Unknown-1; do
    echo "[output]"
    echo "name=$wout"
    echo "scale=1"
    echo
  done
  echo "[input-method]"
  echo "path=libexec/weston-keyboard"
} > "$WESTON_INI" 2>/dev/null && [ -s "$WESTON_INI" ]; then
  export WESTON_CONFIG="$WESTON_INI"
else
  echo "[launcher] could not write $WESTON_INI -- using the shipped SP config"
  export WESTON_CONFIG="$GAMEDIR/picori-weston.ini"
fi
# westonwrap.sh re-parses the VAR=value arguments it is handed as shell
# words, so quoting applied here is gone by the time it runs them. Any
# value containing a space or a newline is therefore split into commands.
# That is not hypothetical: on Knulli, get_controls sets
# SDL_GAMECONTROLLERCONFIG to two mappings on two lines whose names have
# spaces ("Microsoft Xbox 360"), and the launcher died with
#   westonwrap.sh: line 48: Xbox: command not found ... exit code 127
# before tmc_pc was ever reached. muOS sets a single space-free mapping,
# which is why this survived so long untested.
#
# So pass values pre-quoted: shq wraps a value in single quotes and escapes
# any single quote inside it, which survives one round of word splitting
# intact -- spaces, newlines and all. The outer double quotes on the
# substitutions below are load-bearing too: without them the newline
# between two mappings splits the value into two arguments here, and
# westonwrap rejoins them with a space, silently corrupting the second
# mapping (SDL requires them newline-separated).
shq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

# WESTON_CONFIG and PIPEWIRE_RUNTIME_DIR must reach westonwrap itself, not
# just the game, and on sudo-based CFWs $ESUDO is `sudo --preserve-env=<a
# short PortMaster list>`, which drops every other exported variable. So they
# go in Westonpack's documented stack-wide slot: `$ESUDO env VAR=... westonwrap.sh`.
# env receives them as single argv words, so no quoting games are needed there.
$ESUDO env WESTON_CONFIG="$WESTON_CONFIG" PIPEWIRE_RUNTIME_DIR=/run \
  "$weston_dir/westonwrap.sh" drm gl kiosk system \
SDL_VIDEODRIVER=x11 \
${AUDIO_ENV[@]+"${AUDIO_ENV[@]}"} \
OMP_WAIT_POLICY=passive \
XDG_DATA_HOME="$(shq "$XDG_DATA_HOME")" \
SDL_GAMECONTROLLERCONFIG="$(shq "$SDL_GAMECONTROLLERCONFIG")" \
./tmc_pc &
GAME_PID=$!

# Do not foreground the game: see cleanup() above.
wait "$GAME_PID"
status=$?
GAME_PID=""

cleanup
exit "$status"
