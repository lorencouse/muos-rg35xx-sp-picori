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
  - [ ] Playtest on the SP (v2.0.0 installed, saves in place). Findings 2026-09-05, see
        "Playtest findings" below: the v2.0.0 zip shows the LOADING splash forever once the
        menu hint has been dismissed; fixed on the SP by `present_thread: false` (committed).
    - [ ] frame rate in a busy area (tmc_pc ~38-42% CPU in the Minish Woods at the 60 fps target
          with the synchronous present)
    - [ ] audio: device opened 44100 Hz / 1920 frames; listen for dropouts. If it stutters, try
          `echo 4096 > /mnt/mmc/ports/picori/audio_frames` and relaunch
    - [ ] save states: L2 saves to the next slot, Y loads the selected one, overlay Saves tab picks
    - [x] fast-forward on R2 (hold): works; each press/release logs one `[pace] ... vsync=0/1`
          line because fast-forward drops vsync. Expected, not a fault.
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
      https://github.com/lorencouse/muos-rg35xx-sp-picori/releases/tag/v2.0.2 (v2.0.0 is the
      black-screen build, do not link it)
- [ ] Hand EpicNoob the **v2.0.2** zip (not v2.0.0, which goes black after the menu hint) for the
      TSP re-test and ask for `ports/picori/log.txt` back.
- [ ] Device-side only: add a `picori)` case to `/opt/muos/script/mux/menu_tap.sh` that injects 312 so
      physical MENU on this SP opens the settings overlay instead of the pause menu.
- [x] v2.0.1 tagged 2026-09-05: fork release v0.8.3-sp6 (CI run 33999029945, one xmake
      "double free" crash on the x86_64 ABI-check leg, rerun passed), build.sh pinned to the sp6
      binary (sha ab7f8666...). Carries `present_thread: false`, the sp6 binary and `min_glibc`
      2.29. sp6 tested on the SP before tagging: splash centred, the guard logs
      "[present] renderer 'opengles2' is GPU-backed" and the game renders even with
      `present_thread: true`.
  - [x] v2.0.1 release published (second run; the first fetched sp5 because the workflow
        hardcoded the fork tag): picori.zip carries the sp6 binary (sha ab7f8666...),
        present_thread false, min_glibc 2.29. https://github.com/lorencouse/muos-rg35xx-sp-picori/releases/tag/v2.0.1
- [x] v2.0.2 tagged 2026-09-07: `tts_enabled: false` in config.json. bbilford83 heard the fork's
      prelaunch speech on Knulli (espeak present); the SP has no backend so it never showed.
      Same binary and shim as v2.0.1.
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
  - [ ] ask EpicNoob to re-test the v2.0.2 zip and send `ports/picori/log.txt`

- TrimUI Pro S / Knulli Scarab 20260720 (1280x720) and R36S / AmberELEC (Kdog, 2026-09-10, v2.0.2):
  both run. On both he had to set window scale 3 by hand, and the scale setting is itself hard to
  read and needs a restart to take effect.
  - [x] seed `window_scale` from `DISPLAY_WIDTH`/`DISPLAY_HEIGHT` in the launcher, once, next to
        the aspect seed: largest whole multiple of 240x160 that fits (1280x720 -> 4, 640x480 -> 2),
        and only over the shipped default so a hand-picked scale stands. Uses its own
        `conf/.scale` marker, so v2.0.2 installs pick it up on the next launch. Why it matters at
        all when the config says `fullscreen: true`: the game creates the window at
        240x160*scale and asks for fullscreen afterwards, and on those two CFWs the request
        appears not to resize the window.
  - [x] the real reason scale 3 helped him, found by reading the fork: `Port_UiScale()` in
        `port_imgui_menu.cpp` computes min(w/640, h/480) from the *window*, caches it on the
        first call, and that call happens in `Port_ImGui_Init` -- which runs inside
        `Port_PPU_Init`, before `port_main.c:634` asks for fullscreen. With window_scale 1 it
        therefore measures 240x160, clamps to its 0.5 floor and stays there: a half-size
        overlay on any panel, and no way to fix it without a restart. window_scale 3 made the
        pre-fullscreen window 720x480, which measures 1.0. So this is the same defect
        EpicNoob reported as "the menu is very hard to read" on the TSP, not a fullscreen
        failure -- the earlier guess in the window_scale commit. The seed stays (it is what
        both testers did by hand, and it is right for a windowed launch) but it is no longer
        the fix.
  - [x] launcher exports `TMC_UI_SCALE` computed from `DISPLAY_WIDTH`/`DISPLAY_HEIGHT` in
        tenths, clamped to the engine's own 0.5-2.0: 1.5 on 1280x720, 1.0 on 640x480, 0.5 on
        320x240. The env var is read before the window-size guess, so this fixes the overlay
        on every panel with the sp6 binary already shipped -- no CI round trip.
  - [x] `"console_ui": 1` in config.json. The fork's console shell is the D-pad/A/B/L-R
        handheld UI (full-screen, one group at a time, footer legend, B backs out and closes)
        and it is exactly the conventional layout, but `PORT_CONSOLE_UI_AUTO` only picks it
        when the window is <= 860 px wide. A 1280x720 handheld therefore got the desktop
        ribbon -- 15 tabs, hover tooltips, double-click to activate, a corner close button --
        which is what "hard to change this setting in the menu" really was. Pinned on: every
        target device here is a handheld.
  - [x] fork 837f051a6 (`rg35xx-sp-audio-ui`, pushed, needs a CI build and a new tag to reach
        the device): the console shell covered the whole screen, so the Display group hid the
        only evidence for what it changes. A `ConsoleCat` can now be marked `preview`; while
        one is open the shell docks to part of the screen and both present paths fit the game
        frame into the rest. Wide outputs split side by side (the frame is 3:2), squarer ones
        stack; the picture takes 0.46, widens to 0.5 if that is what gives it a whole GBA
        frame, and gets no split at all below that (320x240). 1280x720 -> 589x393 picture
        beside a 691x720 panel; 640x480 -> 331x221 above a 640x259 panel. The game is frozen
        while the menu is up but the present path re-rasterises, so aspect, scale, filter,
        colour correction, persistence and fill all still apply live.
    - [ ] cut a fork release (v0.8.3-sp7?) and repin `TMC_TAG` / `TMC_SHA256` in build.sh, then
          tag v2.1.0 here. Nothing else in this round needs a new binary.
  - [ ] fork follow-up (needs a CI build, so not in this zip): make `Port_UiScale()` read
        `SDL_GetCurrentRenderOutputSize` and recompute on `SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED`
        instead of caching the pre-fullscreen window size -- same fix d573de767 applied to the
        boot splash. Consider also whether AUTO should key off "no mouse" rather than window
        width, so a 720p handheld gets the console shell without the package pinning it.
  - [x] adb smoke on the SP, 2026-09-10 (muOS 2601.1, sp6 binary, new launcher + ini pushed,
        `conf/.scale` removed first): the seed rewrote the device's own `"window_scale": 1` to 2
        -- that copy had been rewritten by the game, so window_scale was the last key with no
        trailing comma, which is the sed's second branch doing its job on busybox --
        `conf/.scale` was created, `TMC_UI_SCALE=1.0` is in the environment of both the
        gptokeyb2 and tmc_pc processes (read from `/proc/<pid>/environ`), and the game reached
        "Entering AgbMain" and drew the title screen (tools/grab-screen.sh).
  - [ ] confirm with Kdog on the next zip: overlay legible at 1280x720 with no hand-editing,
        console shell (not the ribbon) on both devices, and whether scale 4 or his 3 reads
        better on the Pro S. Neither can be checked on the SP: at 640x480 `TMC_UI_SCALE` comes
        out 1.0 (the value the overlay already used) and AUTO already picked the console shell.
  - [x] "L2 save, X or Y load is weird mapping": fixed. Every convention on these devices has
        L = load and R = save (RetroArch: hotkey+L1 load, hotkey+R1 save, hotkey+L2/R2 slot;
        modifier-less ports: bare L2 load, R2 save), and the old ini had L2 saving and a face
        button loading. Now L2 loads the selected slot, Select+L2 saves to a new slot, R2 keeps
        fast-forward and Y goes back to being a soft slot.
    - This re-adds `-H back` and a `[controls:hk_hotkey]` layer, which 4bed584 removed on the
      grounds that Cebion's reference makes the plain `.ini` project policy and that Select
      should keep its game function. Be ready to defend it in the PR: the layer exists only to
      keep save on a modifier so no bare game button is spent on it, and Select is inert in
      Minish Cap outside menus. If a reviewer objects, the fallback with no layer is bare
      L2 = load, Y = save to a new slot.
    - Layer gotcha (from docs/weston-port-notes.md): a key left out of a layer is unbound while
      Select is held, not inherited from `[controls]`, so the layer repeats every other binding
      verbatim. `back` is the one deliberate omission.
    - [x] gptokeyb2 parse checked on the SP (2026-09-10) with
          `cd /mnt/mmc/MUOS/PortMaster && LD_PRELOAD=./libinterpose.aarch64.so ./gptokeyb2 /bin/true -d -H back -c .../picori.ini`:
          prints "set hotkey as back", `[controls]` l2 = "f6" / y = "v" / r2 = "tab", and
          `[controls:hk_hotkey]` l2 = "home" with every other bind repeated and `back =` empty.
          `-H hotkey` is in this build's usage string, so the flag is supported, not tolerated.
    - [ ] still needs a button press on the SP: that L2 loads and Select+L2 saves a new slot,
          that a Select *tap* still reaches the game (the dump cannot show what gptokeyb2 does
          with the modifier on release), and that holding Select does not mute the face buttons
          or the F8 overlay
  - [x] menu button differs per device (Menu on the Pro S, R3 on the R36S): that is the firmware's
        Guide mapping, nothing to change in the package. Noted in the port README's controls table.

## Playtest findings (SP, 2026-09-05, v2.0.0)

Reported: "PROJECT PICORI LOADING" drawn in the top-left corner, load feels like over a minute,
then title music (looping) with nothing on screen.

- [x] Nothing on screen: the game was running (autosaves, title demo loop) but no frame reached
      the panel after the splash. Root cause: the fork's off-thread present worker
      (`port_present_thread.cpp`) was written for the software renderer under X. Through the shim
      the SDL_Renderer is opengles2, whose GL context is current on the main thread, so the
      worker's `SDL_RenderPresent` calls succeed without drawing. The first launches looked fine
      only because the "MENU or Select+Start" hint overlay forces a synchronous main-thread
      present; once `menu_hint_seen` was saved every frame went to the worker. Package fix:
      `present_thread: false` in config.json (commit 32edcf8; also applied on the SP). Fork fix:
      the worker refuses any renderer other than "software" (v0.8.3-sp6).
- [x] Splash in the top-left corner: PaintFrame sized the splash from `SDL_GetWindowSize`, which
      still reports the 240x160 the window asked for at that point. Fork fix in v0.8.3-sp6: use
      `SDL_GetCurrentRenderOutputSize`, fall back to the window size. Verified centred on the SP.
- [x] Load time: measured on the SP with the page cache dropped (`echo 3 > drop_caches`): 12 s
      from launch to "Entering AgbMain"; warm launches show the Nintendo/Capcom logo within 6 s.
      The "over a minute" was the black screen, not loading. Nothing to do.
- [ ] The file-select screen opens the fork's "Port & Randomizer Setup" sidebar on its own
      (seen on the sp6 run with no input). Check whether that is meant to be on by default on a
      handheld; "Close Sidebar" dismisses it.
- [ ] Autosave: with `autosave_enabled` the game writes a 650 KB ring slot every 60 s to the SD
      card (three slots). Harmless so far; watch for hitching on the interval.
