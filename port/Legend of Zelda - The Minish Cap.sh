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

# Non-4:3 panels get integer scaling instead of the 4:3 stretch, once.
if [ ! -f "$GAMEDIR/conf/.aspect" ]; then
  if [ $(( ${DISPLAY_WIDTH:-640} * 3 )) -ne $(( ${DISPLAY_HEIGHT:-480} * 4 )) ]; then
    sed -i 's/"aspect_mode": "stretch"/"aspect_mode": "pixel_perfect"/' "$GAMEDIR/config.json"
  fi
  touch "$GAMEDIR/conf/.aspect"
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

$GPTOKEYB2 "$BINARY" -H back -c "$GAMEDIR/tmc_pc.gptk" &

pm_platform_helper "$GAMEDIR/$BINARY"

SDL_VIDEODRIVER="$GAME_SDL_VIDEODRIVER" SDL_AUDIODRIVER="$GAME_SDL_AUDIODRIVER" ./"$BINARY"

pm_finish
