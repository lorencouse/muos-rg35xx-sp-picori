## Notes

Thanks to [999sian](https://github.com/999sian/tmc) and the Project Picori contributors for the native PC port of *The Minish Cap*, which runs the decompiled game at full speed with save states and a built-in settings menu. Thanks to the [zeldaret](https://github.com/zeldaret/tmc) team for the decompilation and to [bmdhacks](https://github.com/bmdhacks/SDL/tree/sdl2-backend) for the SDL3-to-SDL2 shim.

Source for this build: https://github.com/lorencouse/tmc/tree/rg35xx-sp-audio-ui

This port does not include the game. Copy your ROM into `ports/picori/` as `baserom.gba` (USA), `baserom_eu.gba` or `baserom_jp.gba`. The first launch extracts the game's assets from the ROM and takes about two minutes.

## Controls

| Button | Action |
|--|--|
| D-pad | Move |
| A | Sword / confirm |
| B | Item / cancel |
| X | Extra item slot (assign it in the pause menu) |
| Y | Load the selected save state |
| L1 | GBA L |
| R1 | GBA R |
| L2 | Save state to the next slot |
| R2 (hold) | Fast-forward |
| Start | Pause menu |
| Select | Select |
| Menu | Port settings (also the "L" prompt on the file select) |

Save states are separate from the in-game save. Pick the slot to load in the settings overlay under Saves, which shows a thumbnail per slot.

## Compile

### tmc_pc

Built in a Debian bullseye container on an arm64 host (glibc 2.31 floor). `TMC_SDL3_SHARED=1` links SDL3 as a shared library so the shim below can replace it.

```shell
git clone -b rg35xx-sp-audio-ui https://github.com/lorencouse/tmc.git
cd tmc
git submodule update --init --recursive --depth 1
TMC_SDL3_SHARED=1 python3 build.py --usa --slim
```

The binary is `build/pc/tmc_pc`.

### SDL3-on-SDL2 shim

```shell
git clone --recursive -b sdl2-backend https://github.com/bmdhacks/SDL.git
git clone https://github.com/KhronosGroup/SPIRV-Cross.git
cd SDL && mkdir build && cd build
cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="-march=armv8-a" \
  -DSDL_SDL2_BACKEND=ON \
  -DSDL_SPIRV_CROSS_DIR=../../SPIRV-Cross \
  -DSDL_X11=OFF -DSDL_WAYLAND=OFF -DSDL_KMSDRM=OFF \
  -DSDL_PIPEWIRE=OFF -DSDL_PULSEAUDIO=OFF -DSDL_ALSA=OFF \
  -DSDL_SNDIO=OFF -DSDL_OSS=OFF -DSDL_JACK=OFF \
  -DSDL_OFFSCREEN=OFF -DSDL_DUMMYVIDEO=OFF \
  -DSDL_DUMMYAUDIO=OFF -DSDL_DISKAUDIO=OFF \
  -DSDL_VULKAN=OFF -DSDL_GPU=ON -DSDL_RENDER_GPU=ON \
  -DSDL_UNIX_CONSOLE_BUILD=ON
make -j$(nproc)
```

The shim is `build/libSDL3.so.0.*`.
