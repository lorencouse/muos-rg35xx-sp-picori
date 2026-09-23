#!/bin/bash

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
BINARY="tmc_pc.${DEVICE_ARCH}"

cd "$GAMEDIR"

# Keep the previous run's log: a tester who relaunches after a crash still has it.
[ -f "$GAMEDIR/log.txt" ] && mv -f "$GAMEDIR/log.txt" "$GAMEDIR/log.prev.txt"
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

have_rom() {
  [ -f "$GAMEDIR/baserom.gba" ] || [ -f "$GAMEDIR/baserom_eu.gba" ] || [ -f "$GAMEDIR/baserom_jp.gba" ]
}

# A ROM under any other name (the No-Intro one, say) is recognised by the
# decomp's SHA-1s and renamed to the file the game looks for.
if ! have_rom && command -v sha1sum >/dev/null 2>&1; then
  for rom in "$GAMEDIR"/*.[gG][bB][aA]; do
    [ -f "$rom" ] || continue
    case "$(sha1sum "$rom" | cut -d' ' -f1)" in
      b4bd50e4131b027c334547b4524e2dbbd4227130) name=baserom.gba ;;
      cff199b36ff173fb6faf152653d1bccf87c26fb7) name=baserom_eu.gba ;;
      6c5404a1effb17f481f352181d0f1c61a2765c5d) name=baserom_jp.gba ;;
      *) echo "Not a Minish Cap ROM the port knows: ${rom##*/}"; continue ;;
    esac
    [ -f "$GAMEDIR/$name" ] || { echo "Renaming ${rom##*/} to $name"; mv "$rom" "$GAMEDIR/$name"; }
  done
fi

if ! have_rom; then
  if ls "$GAMEDIR"/*.[zZ][iI][pP] >/dev/null 2>&1 || ls "$GAMEDIR"/*.7[zZ] >/dev/null 2>&1; then
    pm_message "Unzip your Minish Cap ROM first: ports/picori needs the .gba file itself."
  elif ! command -v sha1sum >/dev/null 2>&1; then
    pm_message "Rename your Minish Cap ROM in ports/picori to baserom.gba (USA), baserom_eu.gba or baserom_jp.gba."
  elif ls "$GAMEDIR"/*.[gG][bB][aA] >/dev/null 2>&1; then
    pm_message "The .gba in ports/picori is not a clean Minish Cap ROM (USA, Europe or Japan). Hacked or patched ROMs are not supported."
  else
    pm_message "Copy your Minish Cap ROM (.gba, USA, Europe or Japan) into ports/picori. Any file name works."
  fi
  sleep 5
  exit 1
fi

if [ ! -d "$GAMEDIR/assets" ]; then
  pm_message "First launch: extracting game assets from the ROM. The screen stays black for up to a minute. Do not quit until the title appears."
fi

$ESUDO chmod +x "$GAMEDIR/$BINARY"

mkdir -p "$GAMEDIR/conf"
export XDG_DATA_HOME="$GAMEDIR/conf"
export LD_LIBRARY_PATH="$GAMEDIR/libs.${DEVICE_ARCH}:$LD_LIBRARY_PATH"
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
# Skip the port's desktop ROM/language picker; the ROM is found from the paths above.
export TMC_AUTOPLAY=1

# The zip ships config.default.json, not config.json, so a PortMaster update
# (which overwrites every file in the zip) keeps the player's settings. A fresh
# config.json also clears the first-launch markers so the seeds below re-run.
if [ ! -f "$GAMEDIR/config.json" ]; then
  cp "$GAMEDIR/config.default.json" "$GAMEDIR/config.json"
  rm -f "$GAMEDIR/conf/.aspect" "$GAMEDIR/conf/.scale" "$GAMEDIR/conf/.zoom"
fi

# Configs from before v2.3.0 lack the Select+X/Y picker chords; add the key
# once. A value the player set, true or false, is left alone.
if ! grep -q '"select_state_chords"' "$GAMEDIR/config.json"; then
  sed -i '1s/^{/{"select_state_chords": true,/' "$GAMEDIR/config.json"
fi

# Configs from before v2.3.0 have widescreen off, which the zoomed-out view
# below needs; switch it on once. Turning it off in the settings menu stands.
if [ ! -f "$GAMEDIR/conf/.zoom" ]; then
  sed -i 's/"widescreen_enabled": false/"widescreen_enabled": true/' "$GAMEDIR/config.json"
  touch "$GAMEDIR/conf/.zoom"
fi

PANEL_WIDTH=${DISPLAY_WIDTH:-640}
PANEL_HEIGHT=${DISPLAY_HEIGHT:-480}

# First launch only: non-4:3 panels get integer scaling instead of the 4:3 stretch.
if [ ! -f "$GAMEDIR/conf/.aspect" ]; then
  if [ $(( PANEL_WIDTH * 3 )) -ne $(( PANEL_HEIGHT * 4 )) ]; then
    sed -i 's/"aspect_mode": "stretch"/"aspect_mode": "pixel_perfect"/' "$GAMEDIR/config.json"
  fi
  touch "$GAMEDIR/conf/.aspect"
fi

# First launch only: window_scale = largest whole multiple of 240x160 that fits
# the panel (1280x720 -> 4, 640x480 -> 2). The game opens its window at
# 240x160 * window_scale before it asks for fullscreen; on Knulli and AmberELEC
# that request left a scale-1 window postage-stamp sized. Only the shipped
# default is rewritten, so a scale picked in the settings menu stands.
if [ ! -f "$GAMEDIR/conf/.scale" ]; then
  scale=$(( PANEL_WIDTH / 240 ))
  scale_v=$(( PANEL_HEIGHT / 160 ))
  [ "$scale_v" -lt "$scale" ] && scale=$scale_v
  [ "$scale" -lt 1 ] && scale=1
  [ "$scale" -gt 10 ] && scale=10
  if [ "$scale" -ne 1 ]; then
    sed -i -e "s/\(\"window_scale\"[[:space:]]*:[[:space:]]*\)1,/\1$scale,/" \
           -e "s/\(\"window_scale\"[[:space:]]*:[[:space:]]*\)1\$/\1$scale/" \
           "$GAMEDIR/config.json"
  fi
  touch "$GAMEDIR/conf/.scale"
fi

# Settings-menu text scale from the panel, in tenths, clamped to the game's
# 0.5-2.0 range (1.0 on 640x480, 1.5 on 1280x720). The game would otherwise
# size it from its pre-fullscreen 240x160 window and pin it at the floor.
ui_tenths=$(( PANEL_WIDTH * 10 / 640 ))
ui_tenths_v=$(( PANEL_HEIGHT * 10 / 480 ))
[ "$ui_tenths_v" -lt "$ui_tenths" ] && ui_tenths=$ui_tenths_v
[ "$ui_tenths" -lt 5 ] && ui_tenths=5
[ "$ui_tenths" -gt 20 ] && ui_tenths=20
export TMC_UI_SCALE="${TMC_UI_SCALE:-$(( ui_tenths / 10 )).$(( ui_tenths % 10 ))}"

# Zoomed-out view: at the largest whole multiple that still shows 240x160, a
# panel that divides exactly shows more world than the GBA did (640x480 ->
# 320x240 at 2x, 1280x720 -> 320x180 at 4x). The game uses that size in rooms
# big enough to fill it and the GBA's 240x160 everywhere else, so the picture
# always fills the panel. Other panels (720x720 -> 240x240) keep 240x160.
zoom=$(( PANEL_WIDTH / 240 ))
zoom_v=$(( PANEL_HEIGHT / 160 ))
[ "$zoom_v" -lt "$zoom" ] && zoom=$zoom_v
if [ "$zoom" -ge 1 ]; then
  view_w=$(( PANEL_WIDTH / zoom ))
  view_h=$(( PANEL_HEIGHT / zoom ))
  if [ $(( view_w * zoom )) -eq "$PANEL_WIDTH" ] && [ $(( view_h * zoom )) -eq "$PANEL_HEIGHT" ] &&
     [ "$view_w" -gt 240 ] && [ "$view_w" -le 384 ] && [ "$view_h" -le 240 ]; then
    export TMC_WS_VIEW_WIDTH="${TMC_WS_VIEW_WIDTH:-$view_w}"
    [ "$view_h" -gt 160 ] && export TMC_WS_VIEW_HEIGHT="${TMC_WS_VIEW_HEIGHT:-$view_h}"
  fi
fi

# SDL3 shim: pass the CFW's SDL2 driver choice through to the SDL2 underneath.
GAME_SDL_VIDEODRIVER=""
if [ -n "$SDL_VIDEODRIVER" ]; then
  export SDL3SHIM_SDL2_VIDEODRIVER="$SDL_VIDEODRIVER"
  GAME_SDL_VIDEODRIVER=sdl2
fi

GAME_SDL_AUDIODRIVER=""
if [ -n "$SDL_AUDIODRIVER" ]; then
  export SDL3SHIM_SDL2_AUDIODRIVER="$SDL_AUDIODRIVER"
  GAME_SDL_AUDIODRIVER=sdl2
fi

$GPTOKEYB2 "$BINARY" -c "$GAMEDIR/picori.ini" &

pm_platform_helper "$GAMEDIR/$BINARY"

SDL_VIDEODRIVER="$GAME_SDL_VIDEODRIVER" SDL_AUDIODRIVER="$GAME_SDL_AUDIODRIVER" ./"$BINARY"

pm_finish
