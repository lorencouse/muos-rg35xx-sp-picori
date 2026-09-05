# TODO

## Before the PortMaster PR

- [x] Fork: `portmaster-shared-sdl3` merged into `rg35xx-sp-audio-ui`, release `v0.8.3-sp5` published
      (2026-09-05) with tmc_pc linked against shared SDL3. Eight CI runs: the bullseye container now
      installs from snapshot.debian.org because the Debian CDN 404s on bullseye-security.
- [x] `TMC_SHA256` pinned in `build.sh`; `v2.0.0` tag pushed, workflow builds shim + zip.
      Shim: bmdhacks/SDL@6057d79, glibc floor 2.29, NEEDED only libc/libm/libdl/libgcc_s/libpthread.
- [x] SP test over adb (2026-09-05, muOS 2601.1): boots through the shim (video driver sdl2,
      SDL_Renderer opengles2), title and file select render correctly at 640x480 stretch, pad
      reaches the game via gptokeyb2, guide (312) opens the F8 overlay, Start+Select quits and the
      frontend returns. Fixes made during the test:
      - `render_backend: software`, `gpu_raster: false` in config.json: with the shim SDL_GPU
        creates a GLES device and then SIGSEGVs inside libSDL2 (bugreport backtrace).
      - `TMC_AUTOPLAY=1` in the launcher: the fork shows a desktop ROM/language picker before the
        game; on a handheld that is an extra Start press every boot.
  - [ ] Playtest on the SP (v2.0.0 installed, saves in place):
    - [ ] frame rate in a busy area (tmc_pc sat at ~35% CPU on the title at the 60 fps target)
    - [ ] audio: device opened 44100 Hz / 1920 frames; listen for dropouts. If it stutters, try
          `echo 4096 > /mnt/mmc/ports/picori/audio_frames` and relaunch
    - [ ] save states: L2 saves to the next slot, Y loads the selected one, overlay Saves tab picks
    - [ ] fast-forward on R2 (hold)
    - [ ] muOS volume keys and sleep/dim behave normally while the game runs
  - [ ] physical MENU on this SP goes through the custom menu_tap.sh, which injects Start for ports
        not in its list; add `picori)` -> 312 there if MENU should open the overlay on this device
        (device-side, not a package change)
  - [x] `min_glibc`: sp5 binary GLIBC_2.29 (no GLIBCXX), shim GLIBC_2.29; port.json now says 2.29
        (the v2.0.0 zip still carries 2.31; the next tag picks up 2.29)
- [x] Cebion's porting reference (~/Downloads/portmaster-ai-complete-reference.md): checked. Changes made:
      gptokeyb2 `.ini` instead of `.gptk` (project policy), no `-H` flag, Select+L2/R2 slot combos
      dropped (slot picking lives in the overlay's Saves tab), gptokeyb2 licence added,
      testing_thread.txt added (kept out of the zip), README thank-you rewritten, packaging comments
      removed from the Compile section, no em dashes anywhere in port/.
- [ ] PR description must use the PortMaster PR template and honestly tick the AI-assisted box:
      be able to explain every non-standard line (the aspect seed and the SDL3SHIM passthrough).
- [ ] Reply to Cebion on Discord in my own words. Facts to lean on: template launcher, gptokeyb2
      ini, port.json v4, mixv1 cover, sdl3shim instead of weston, source branch cited in README and
      port.json, tested on the SP (muOS). v2.0.0 zip:
      https://github.com/lorencouse/muos-rg35xx-sp-picori/releases/tag/v2.0.0
- [ ] Hand EpicNoob the v2.0.0 zip for the TSP re-test and ask for `ports/picori/log.txt` back.
- [ ] Device-side only: add a `picori)` case to `/opt/muos/script/mux/menu_tap.sh` that injects 312 so
      physical MENU on this SP opens the settings overlay instead of the pause menu.
- [ ] Next tag (v2.0.1 or later) picks up `min_glibc` 2.29; the v2.0.0 zip says 2.31.
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
