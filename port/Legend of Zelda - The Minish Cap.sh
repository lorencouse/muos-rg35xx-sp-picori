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

> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

if [ ! -f "$GAMEDIR/baserom.gba" ] && [ ! -f "$GAMEDIR/baserom_eu.gba" ] && [ ! -f "$GAMEDIR/baserom_jp.gba" ]; then
  pm_message "Copy your Minish Cap ROM to ports/picori as baserom.gba (USA), baserom_eu.gba or baserom_jp.gba."
  sleep 5
  exit 1
fi

if [ ! -d "$GAMEDIR/assets" ]; then
  pm_message "First launch: extracting game assets from the ROM. This takes about two minutes."
fi

mkdir -p "$GAMEDIR/conf"
export XDG_DATA_HOME="$GAMEDIR/conf"
export LD_LIBRARY_PATH="$GAMEDIR/libs.${DEVICE_ARCH}:$LD_LIBRARY_PATH"
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
export TMC_AUTOPLAY=1

PANEL_WIDTH=${DISPLAY_WIDTH:-640}
PANEL_HEIGHT=${DISPLAY_HEIGHT:-480}

# Non-4:3 panels get integer scaling instead of the 4:3 stretch, once.
if [ ! -f "$GAMEDIR/conf/.aspect" ]; then
  if [ $(( PANEL_WIDTH * 3 )) -ne $(( PANEL_HEIGHT * 4 )) ]; then
    sed -i 's/"aspect_mode": "stretch"/"aspect_mode": "pixel_perfect"/' "$GAMEDIR/config.json"
  fi
  touch "$GAMEDIR/conf/.aspect"
fi

# Seed window_scale from the panel, once. The game creates its window at
# 240x160 times this scale and only then asks for fullscreen; where that
# request is a no-op (reported on Knulli/TrimUI Pro S at 1280x720 and on
# AmberELEC/R36S) scale 1 leaves a postage-stamp window, and the scale
# setting itself is then too small to read in the overlay. Take the largest
# whole multiple that fits the panel, capped at the game's own limit of 10.
# The sed only matches the shipped default, so a hand-picked scale stands.
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

$GPTOKEYB2 "$BINARY" -H back -c "$GAMEDIR/picori.ini" &

pm_platform_helper "$GAMEDIR/$BINARY"

SDL_VIDEODRIVER="$GAME_SDL_VIDEODRIVER" SDL_AUDIODRIVER="$GAME_SDL_AUDIODRIVER" ./"$BINARY"

pm_finish
