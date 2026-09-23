## Notes

Thanks to [999sian](https://github.com/999sian/tmc) and the Project Picori contributors for the native PC port of *The Legend of Zelda: The Minish Cap*, to the [zeldaret](https://github.com/zeldaret/tmc) team for the decompilation it is built on, and to [bmdhacks](https://github.com/bmdhacks/SDL/tree/sdl2-backend) for the SDL3-to-SDL2 shim that lets an SDL3 program run on these handhelds.

**This port does not include the game.** Copy your ROM into `ports/picori/`, unzipped. The launcher recognises a clean USA, Europe or Japan ROM under any file name and renames it to `baserom.gba`, `baserom_eu.gba` or `baserom_jp.gba`; you can also name it that way yourself. The first launch extracts the game assets from the ROM into `ports/picori/assets/`; later launches skip that. Let the first launch finish: quitting while the screen is still black interrupts the extraction.

## Controls

| Button | Action |
|--|--|
| D-pad / left stick | Move |
| A | Sword / confirm |
| B | Item / cancel |
| X / Y | Extra item buttons (see below) |
| Select + X | Save-state picker, ready to save |
| Select + Y | Save-state picker, ready to load |
| L1 | GBA L |
| R1 | GBA R |
| L2 | Save a state to a new slot |
| R2 (hold) | Fast-forward |
| Start | Pause menu |
| Select | Select (Ezlo's hint) |
| Menu (Guide) | Port settings |
| Start + Select | Quit (does not save; see below) |

The settings menu opens on whichever button your firmware reports as the controller's Guide button: Menu on muOS and Knulli, R3 on the R36S under AmberELEC. It is a handheld menu, one group of settings at a time: D-pad moves, A opens or toggles a row, B backs out and closes it from the top level, L1 and R1 step through the groups. The footer lists the buttons. The launcher sizes its text from the panel, so nothing in it needs a mouse or a restart.

## Save states

Save states are separate from the in-game save. L2 takes one at any time and rolls through twenty slots, so a run leaves a history instead of one overwritten state. The game also autosaves to a three-slot ring every minute.

Select + X and Select + Y open the picker, a full-screen page with one slot's screenshot, when it was written, and a filmstrip of the neighbouring slots. Select + X opens it ready to save, Select + Y ready to load, and A does whichever the page is on. Left and right move one slot, up and down (or L1 and R1) jump five, B closes. Pressing X or Y inside the picker switches the page instead of acting, so arriving through the wrong door costs one press and never a run.

In gameplay the game only sees Select once it is clear you are not reaching for X or Y: a tap reaches it when you let go, a hold after a third of a second. Ezlo's hint still comes up either way.

## Extra item buttons

X and Y each hold a third and fourth item alongside A and B. To fill one, open the pause menu's item screen, hold Select, and press A on an item for X or B for Y. Once a button holds an item, pressing X or Y on another item in the pause menu swaps it. L + A and L + B also use the X and Y items. The Menu button's settings have the same slots under "Extra equip slots". The choices are kept in `ports/picori/`, not in the save file, and a button only fires an item the current save owns.

## Saves

Start + Select closes the game at once, without saving. Save in the game or take a state with L2 first; the autosave ring holds at most the last minute.

The in-game save (`tmc.sav`), the save states (`state_*.bin`), the config and the extracted assets all live in `ports/picori/`. Updating the port through PortMaster keeps your settings. Deleting the port folder removes them; copying the folder to another card keeps them.

## Known issues

- The first launch after copying the ROM spends some seconds extracting assets before anything is drawn. Later launches show the Nintendo logo within a few seconds.

## Source

Built from the `rg35xx-sp-audio-ui` branch of <https://github.com/lorencouse/tmc>, a fork of [999sian/tmc](https://github.com/999sian/tmc) that adds a linear audio resampler, a bigger audio buffer for Linux handhelds, a scalable handheld settings menu, a stretch aspect mode and the save-state picker.

Licensed GPL-3.0-or-later, same as Project Picori. Third-party licences are in `picori/licenses/`.

## Compile

### tmc_pc

Built in a Debian bullseye container on an arm64 host, so the binary loads on old CFW glibc (it needs GLIBC 2.29). `TMC_SDL3_SHARED=1` links SDL3 as a shared library so the shim below can replace it.

```shell
git clone -b rg35xx-sp-audio-ui https://github.com/lorencouse/tmc.git
cd tmc
git submodule update --init --recursive --depth 1
TMC_SDL3_SHARED=1 python3 build.py --usa --slim
```

The binary is `build/pc/tmc_pc`, shipped as `picori/tmc_pc.aarch64`.

### SDL3-on-SDL2 shim

```shell
git clone -b sdl2-backend https://github.com/bmdhacks/SDL.git
git -C SDL checkout 6057d79baf8321bf190479a699655f06cc2a962f
git clone https://github.com/KhronosGroup/SPIRV-Cross.git
git -C SPIRV-Cross checkout 00ae9b44c9c16561bdff2e094c518a89f756944b
cd SDL && mkdir build && cd build
cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="-march=armv8-a" \
  -DSDL_SDL2_BACKEND=ON \
  -DSDL_SPIRV_CROSS_DIR="$(cd ../../SPIRV-Cross && pwd)" \
  -DSDL_X11=OFF -DSDL_WAYLAND=OFF -DSDL_KMSDRM=OFF \
  -DSDL_PIPEWIRE=OFF -DSDL_PULSEAUDIO=OFF -DSDL_ALSA=OFF \
  -DSDL_SNDIO=OFF -DSDL_OSS=OFF -DSDL_JACK=OFF \
  -DSDL_OFFSCREEN=OFF -DSDL_DUMMYVIDEO=OFF \
  -DSDL_DUMMYAUDIO=OFF -DSDL_DISKAUDIO=OFF \
  -DSDL_VULKAN=OFF -DSDL_GPU=ON -DSDL_RENDER_GPU=ON \
  -DSDL_UNIX_CONSOLE_BUILD=ON \
  -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF
make -j$(nproc)
```

The shim is `build/libSDL3.so.0.*`, shipped as `picori/libs.aarch64/libSDL3.so.0`.
