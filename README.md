# muos-rg35xx-sp-picori

PortMaster packaging for [Project Picori](https://github.com/999sian/tmc), the
PC port of *The Legend of Zelda: The Minish Cap*. The player-facing README is
[`port/README.md`](port/README.md).

## Layout

```
port/                                   the package, as PortMaster wants it
  Legend of Zelda - The Minish Cap.sh   launcher
  port.json  gameinfo.xml  README.md  screenshot.png  cover.png
  picori/
    config.json                         shipped settings (keyboard bindings only)
    picori.ini                          gptokeyb2 keyboard map
    licenses/
    tmc_pc.aarch64                      added by build.sh, not in git
    libs.aarch64/libSDL3.so.0           added by build.sh, not in git
build.sh                                assembles dist/<version>/picori.zip
.github/workflows/release.yml           builds the shim and the zip on a v* tag
tools/grab-screen.sh                    fb0 screenshot over adb
docs/weston-port-notes.md               notes from the earlier weston-based launcher
```

## How it runs

`tmc_pc` is an SDL3 program. The handhelds ship SDL2, so the package runs it
against the [SDL3-on-SDL2 shim](https://github.com/bmdhacks/SDL/tree/sdl2-backend)
(`libs.aarch64/libSDL3.so.0`), the same way the Insaniquarium, Arcanum CE and
Open Chaos ports do. That needs a `tmc_pc` linked against a *shared* SDL3,
which the fork builds when `TMC_SDL3_SHARED=1` (linux-arm64 leg of its CI).

Input goes through gptokeyb2 as a keyboard: the port's save-state and
fast-forward actions are keyboard-only, and `config.json` ships without its
gamepad bindings so a button is not seen twice.

## Build

```sh
./build.sh 2.0.0                       # dist/2.0.0/picori.zip
TMC_BINARY=./tmc_pc SDL3SHIM_LIB=./libSDL3.so.0 ./build.sh 2.0.0-dev
```

`build.sh` downloads `tmc_pc` from the fork release named by `TMC_TAG`
(default `v0.8.3-sp5`) and the shim from this repo's `sdl3shim` release
unless both are given locally. Pushing a `v*` tag runs the workflow, which
builds the shim in a Debian bullseye arm64 container (glibc 2.31) and attaches
`picori.zip` and `libSDL3.so.0` to the release.

## Where the binary comes from

`tmc_pc` is built from the `rg35xx-sp-audio-ui` branch of
[lorencouse/tmc](https://github.com/lorencouse/tmc), a fork of 999sian/tmc
that adds a linear audio resampler, a 44.1 kHz synth rate, a UI scale for
small screens and a stretch aspect mode. Its CI builds the linux-arm64 leg
in a bullseye container so the binary loads on old CFW glibc.

## Status

Reworked on 2026-09-05 against the PortMaster review and Cebion's porting
reference: template launcher, port.json v4, gptokeyb2 ini, mixv1 cover,
sdl3shim instead of weston.
Not yet run on hardware in this form. Before a PortMaster PR it needs the
fork release cut with `TMC_SDL3_SHARED=1`, a device test on muOS, and
testing on the other CFWs.

## Licence

GPL-3.0-or-later, same as Project Picori. No game data is included.
