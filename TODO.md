# TODO

## Before the PortMaster PR

- [ ] Push the fork branch `portmaster-shared-sdl3` (local clone `~/Documents/Development/picori`,
      remote `lorencouse`), merge into `rg35xx-sp-audio-ui`, tag `v0.8.3-sp5`.
      It links SDL3 shared (`TMC_SDL3_SHARED=1`) so the sdl3shim can replace it.
- [ ] Push a `v2.0.0` tag here: the workflow builds the shim (bullseye arm64) and attaches
      `picori.zip` + `libSDL3.so.0` to the release. Then pin `TMC_SHA256` in `build.sh`.
- [ ] Test on the RG35XX SP over adb. Nothing in the reworked package has run on hardware.
  - [ ] frame rate without the governor pin
  - [ ] audio through SDL2 (the PipeWire clock forcing is gone)
  - [ ] MENU opens the overlay (guide -> F8 via gptokeyb2)
  - [ ] glibc floor of the shim (`min_glibc` in port.json says 2.31)
  - [ ] save states (L2 / Y) and fast-forward (R2) still work with keyboard-only bindings
  - [ ] Start+Select quits (gptokeyb2 default hotkey is Select)
- [x] Cebion's porting reference (~/Downloads/portmaster-ai-complete-reference.md): checked. Changes made:
      gptokeyb2 `.ini` instead of `.gptk` (project policy), no `-H` flag, Select+L2/R2 slot combos
      dropped (slot picking lives in the overlay's Saves tab), gptokeyb2 licence added,
      testing_thread.txt added (kept out of the zip), README thank-you rewritten, packaging comments
      removed from the Compile section, no em dashes anywhere in port/.
- [ ] PR description must use the PortMaster PR template and honestly tick the AI-assisted box:
      be able to explain every non-standard line (the aspect seed and the SDL3SHIM passthrough).
- [ ] Reply to Cebion on Discord in my own words.
- [ ] Testing on other CFWs (ArkOS, ROCKNIX, AmberELEC) and resolutions (720x720, 1280x720),
      documented in `#testing-n-dev` before opening the PR.

## Tester reports

- TrimUI Smart Pro, muOS (EpicNoob, 2026-09-04, old weston build): runs, but audio is choppy
  and the menu is very hard to read.
  - [x] menu legibility on 1280x720: the overlay scale was fixed at 1.0 for any window over
        400 px wide, so on 1280x720 it was half the size it is on the SP. Fork branch
        `portmaster-shared-sdl3` now scales it by min(w/640, h/480) (1.5 on the TSP);
        `TMC_UI_SCALE` still overrides. Needs a TSP re-test once v0.8.3-sp5 is out.
  - [x] audio dropouts: the old launcher forced the SP's PipeWire clock (44.1 kHz / 768 quantum)
        on every CFW with pw-metadata, TSP included, and the binary used SDL's default buffer on
        Linux. The new package drops the PipeWire forcing, and the fork now applies the
        TMC_AUDIO_FRAMES / audio_frames / bigger-default-buffer logic (2048 frames) on Linux
        aarch64, not just Android. Needs a TSP re-test; if still choppy, try
        `echo 4096 > ports/picori/audio_frames`.
  - [ ] ask EpicNoob to re-test the v2.0.0 zip and send `ports/picori/log.txt`
