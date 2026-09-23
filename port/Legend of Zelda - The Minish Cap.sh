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

have_rom() {
  [ -f baserom.gba ] || [ -f baserom_eu.gba ] || [ -f baserom_jp.gba ]
}

# Rename a ROM under any other name to the file the game reads, by SHA-1.
if ! have_rom; then
  for rom in *.[gG][bB][aA]; do
    [ -f "$rom" ] || continue
    case "$(sha1sum "$rom" | cut -d' ' -f1)" in
      b4bd50e4131b027c334547b4524e2dbbd4227130) name=baserom.gba ;;
      cff199b36ff173fb6faf152653d1bccf87c26fb7) name=baserom_eu.gba ;;
      6c5404a1effb17f481f352181d0f1c61a2765c5d) name=baserom_jp.gba ;;
      *) continue ;;
    esac
    [ -f "$name" ] || mv "$rom" "$name"
  done
fi

if ! have_rom; then
  pm_message "Copy an unzipped, unmodified Minish Cap ROM (.gba, USA, Europe or Japan) into ports/picori."
  sleep 5
  exit 1
fi

if [ ! -d "$GAMEDIR/assets" ]; then
  pm_message "First launch: extracting game assets from the ROM. The screen stays black for up to a minute."
fi

$ESUDO chmod +x "$GAMEDIR/$BINARY"

mkdir -p "$GAMEDIR/conf"
export XDG_DATA_HOME="$GAMEDIR/conf"
export LD_LIBRARY_PATH="$GAMEDIR/libs.${DEVICE_ARCH}:$LD_LIBRARY_PATH"
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
export TMC_AUTOPLAY=1

DISPLAY_WIDTH=${DISPLAY_WIDTH:-640}
DISPLAY_HEIGHT=${DISPLAY_HEIGHT:-480}

# config.json is not in the zip, so an update keeps the player's settings.
# First launch: whole-number window scale for the panel, and pixel perfect on non-4:3 panels.
if [ ! -s "$GAMEDIR/config.json" ]; then
  cp "$GAMEDIR/config.default.json" "$GAMEDIR/config.json"
  scale=$(( DISPLAY_WIDTH / 240 < DISPLAY_HEIGHT / 160 ? DISPLAY_WIDTH / 240 : DISPLAY_HEIGHT / 160 ))
  [ "$scale" -lt 1 ] && scale=1
  sed -i "s/\"window_scale\": 1,/\"window_scale\": $scale,/" "$GAMEDIR/config.json"
  if [ $(( DISPLAY_WIDTH * 3 )) -ne $(( DISPLAY_HEIGHT * 4 )) ]; then
    sed -i 's/"aspect_mode": "stretch"/"aspect_mode": "pixel_perfect"/' "$GAMEDIR/config.json"
  fi
fi

# Settings-menu text scale, 0.5-2.0 (1.0 at 640x480, 1.5 at 1280x720).
ui=$(( DISPLAY_WIDTH * 10 / 640 < DISPLAY_HEIGHT * 10 / 480 ? DISPLAY_WIDTH * 10 / 640 : DISPLAY_HEIGHT * 10 / 480 ))
[ "$ui" -lt 5 ] && ui=5
[ "$ui" -gt 20 ] && ui=20
export TMC_UI_SCALE="${TMC_UI_SCALE:-$(( ui / 10 )).$(( ui % 10 ))}"

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
