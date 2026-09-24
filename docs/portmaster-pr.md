# PortMaster submission

Everything needed to open the PR against
[PortsMaster/PortMaster-New](https://github.com/PortsMaster/PortMaster-New),
kept here so the repo, not a chat log, holds it.

Current zip: https://github.com/lorencouse/muos-rg35xx-sp-picori/releases/tag/v2.3.0
(tmc v0.8.3-sp10). Do not link v2.0.0, the black-screen build. Save states
from v2.2.0 and earlier do not load in v2.3.0 (quicksave format v8); in-game
saves carry over.

## Steps

1. Build and check the zip: `./build.sh <version>` (CI does the same on a
   `v*` tag and attaches `picori.zip` to the release).
2. Fork PortMaster-New, disable GitHub Actions in the fork's settings, clone
   it with a sparse checkout (their README links JeodC's gist), and run
   `tools/prepare_repo.sh` from its root.
3. `tools/stage-portmaster.sh <version> <checkout>` unpacks the zip into
   `ports/picori/` in the layout the template asks for:
   `port.json`, `README.md`, `screenshot.png`, `cover.png`, `gameinfo.xml`,
   `Legend of Zelda - The Minish Cap.sh`, `picori/`.
4. In the checkout: `python3 tools/build_release.py --do-check`. Fix anything
   it flags. No file here is over 90 MB, so `build_data.py` is not needed.
5. Commit on a branch named `picori`, push, open the PR with the text below.
6. Post the testing thread text (`port/testing_thread.txt`) with the zip link
   in `#testing-n-dev` if that has not happened for this version.

## PR text

```
## Game Information
- **New Port for**: The Legend of Zelda: The Minish Cap (Project Picori)
- **URL**: https://github.com/lorencouse/tmc/tree/rg35xx-sp-audio-ui (fork of https://github.com/999sian/tmc)

## Authorship & Testing

- [x] I wrote and understand this script/patch myself, or clearly marked which parts came from an AI assistant and reviewed them
- [x] I can explain every non-standard line in my launch script

Parts of the launcher, the port README and the engine fork were written with
an AI assistant (Claude). Every line was reviewed and tested on hardware by me;
the non-standard launcher blocks are explained below.

## Submission Requirements

### CFW Tests
- [ ] ArkOS
- [x] AmberELEC (R36S, tester)
- [ ] ROCKNIX
- [x] muOS (RG35XX SP, me; TrimUI Smart Pro, tester)
- [x] Knulli (TrimUI Pro S, tester)
- [ ] Crossmix (Optional)
- [ ] Other (add here)

### Resolution Tests
- [ ] 480x320 (Optional)
- [x] 640x480
- [ ] 720x720 (RGB30) (Optional)
- [x] Higher resolutions (e.g., 1280x720)

## Notes

Not ready to run: the player supplies the Minish Cap ROM; the port extracts the
game assets from it on first launch. No game data is in the package.

The binary is an SDL3 program and runs on the SDL3-on-SDL2 shim
(bmdhacks/SDL, sdl2-backend), the same way the Insaniquarium, Arcanum CE and
Open Chaos ports do. The shim and tmc_pc are built in a Debian bullseye
container (aarch64, GLIBC 2.29 floor, measured with objdump). Input goes
through gptokeyb2 as a keyboard because the port's save-state and fast-forward
actions are keyboard-only.

Non-standard launcher lines, and why:

- The ROM block: a `.gba` under any other name is matched against the
  decomp's SHA-1s for the USA, EU and JP ROMs and renamed to the file the
  port reads. Nothing is renamed without a hash match.
- `TMC_AUTOPLAY=1`: the port shows a desktop ROM/language picker before the
  game; on a handheld that is an extra Start press every boot.
- `config.default.json` is copied to `config.json` only when there is none
  (or it is empty). PortMaster overwrites every file in the zip on an update,
  so shipping `config.json` itself reset the player's settings each time.
  On that first copy the launcher sets `window_scale` (largest whole multiple
  of 240x160 that fits `DISPLAY_WIDTH`x`DISPLAY_HEIGHT`) and, on non-4:3
  panels, `aspect_mode` pixel_perfect: the port opens its window at
  240x160 x `window_scale` before going fullscreen, and a 1280x720 Knulli
  and an R36S got a postage-stamp window at scale 1.
- `TMC_UI_SCALE` from the panel size: the port otherwise sizes its settings
  menu text from the pre-fullscreen window, unreadable at 1280x720.
- `SDL3SHIM_SDL2_VIDEODRIVER` / `SDL3SHIM_SDL2_AUDIODRIVER`: the shim's own way
  of passing the CFW's SDL2 driver choice through, copied from the
  Insaniquarium launcher.
```

## Tester follow-ups

Facts to reply with, in your own words:

- **joshuarcastillo** (RG35XX Plus, muOS, v2.0.2, "unable to create save
  file"): the card was full and the port filled it. Free space, then delete
  `ports/picori/assets_src`, or install the new zip, which no longer writes
  that folder and cleans a leftover one up. First launch re-extracts.
- **CrispTheBunz** (R36S, DARKOSRE, segfaults during boot): ask for
  `ports/picori/log.txt`, the `bugreport_*` folder next to the binary
  (`backtrace.txt` is the one that matters), and which zip. The R36S runs on
  AmberELEC, so this is the CFW or its SDL, not the device.
- **EpicNoob** (TrimUI Smart Pro, muOS): re-test the new zip, which fixes the
  menu size at 1280x720 and the audio buffer, and send `ports/picori/log.txt`.
- **Cebion**: template launcher, gptokeyb2 ini, port.json v4, mixv1 cover,
  sdl3shim instead of weston, source branch in README and port.json, tested on
  the SP. Link the latest release, not v2.0.0 (the black-screen build).

## Still open before the PR

- ArkOS and ROCKNIX runs, from testers; 720x720 if anyone has an RGB30.
- A longer play session on the SP for audio dropouts and autosave hitching.
  Measured so far: 55 fps drawn at 60 tps in the Minish Woods with a text box
  up, through the shim's GLES2 renderer.
