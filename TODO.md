# TODO

## Where it stands (2026-09-17)

- Package `v2.2.0` tagged and built by CI from fork `v0.8.3-sp8`; the fork's release job
  needed its linux tarballs uploaded by hand (GitHub upload flake) and the draft published.
- Fork `v0.8.3-sp8` tagged: runtime_only extraction, loader survives a broken
  `assets_src`, ENOSPC in the log, and the save-state picker (X = save page,
  Y = load page), all verified on the SP. The picker was driven over adb by
  writing key events to gptokeyb2's uinput node (see the memory note).
- Package: launcher trimmed to the template plus the documented seeds,
  README in the PortMaster section layout, `port.json` items with the
  directory slash, testing thread current. `docs/portmaster-pr.md` holds the
  PR text and the tester replies; `tools/stage-portmaster.sh` lays the zip
  out in a PortMaster-New checkout for `build_release.py --do-check`.
- Left for hands and other people: ArkOS and ROCKNIX runs, a long play
  session on the SP for audio and autosave hitching, the three tester replies,
  the Cebion reply, opening the PR.

## Release sp10 / v2.3.0 (2026-09-23)

- Code review of the day's merges (fork a27b4f578^..dcc1099cf plus the package) found ten
  issues; all fixed on fork branch `release-fixes`, fast-forwarded into fork `master` and
  `rg35xx-sp-audio-ui`, tagged `v0.8.3-sp10`.
  - save states written to a `.tmp` and renamed (fsync for manual saves only; autosaves run on
    the game thread on every room change and skip it); config.json likewise, without fsync
  - hidden classic page-stack menu took Start (Enter) / Select (Backspace) / L2 (Home) under the
    console shell: two Starts ran "Unlock all items". Only the shown menu takes raw keys now.
  - file-select sidebar left an ImGui nav key held after closing; sprites below a native
    160-line frame wrapped to the top in the tall view (both sprite passes)
  - tunic colour recoloured any row with a tunic ramp (Grey NPCs); now needs Link's other colours
  - fast_forward_speed cap in the legacy coupled loop; TMC_WS_TRACE read once
  - regression tests: stubs for the new hooks, persistence runner include paths; upstream's
    quicksave_entities dropped (tests relocation the fork's quicksave does not do)
  - CI: tracker repro used a MULTI_REGION-only symbol, breaking the single-region x86_64 build
- Verified on the SP (user, 2026-09-23): Select+X/Y, X/Y items, Equipment assignment, sliders,
  red tunic, zoomed-out view, no cheat on Start.
- Package: autosave every 5 min (was 60 s), launcher DISPLAY_* fallbacks and a set
  TMC_UI_SCALE kept, build.sh pinned to sp10.

## Soft slots back on X/Y, upstream merge (2026-09-23)

Discord 2026-09-19..23: joshuarcastillo (rando works on v2.2.0; "random non functional doors
all over the place", harmless), NoseDevilEugen (README's "Nothing in the game assigns an item
to them on a handheld" is wrong; he wrote the upstream pause-menu soft-slot equip, PR #183;
suggested rebasing on current Picori).

- The README claim was wrong twice over: the fork already had Select+A/B in the pause menu
  (REBORN_FEAT_SELECT_HOLD_EQUIP, default on) to fill soft slots 0/1 and L+A/B
  (REBORN_FEAT_SECONDARY_LAB) to fire them, plus the "Extra equip slots" settings page.
- [x] Fork branch `sp9-upstream-merge` (worktree `../picori-sp9`): upstream master merged
      (59 commits, v0.9.0..v0.9.3 and later). Conflicts in 8 files; quicksave keeps ours
      (full-global regions + engine resume, already a superset of upstream's v7 relocation),
      mixdown keeps ours on upstream's shutdown-safe scratch plus a NaN guard. RA (new, default
      on, needs libcurl) is compiled out when `TMC_SDL3_SHARED=1`.
- [x] Select chords (fork, `select_state_chords`, default off; package turns it on): in gameplay
      Select+X / Select+Y open the picker's save / load page and X/Y are soft slots again.
      Select is held back from the game in gameplay (a tap is replayed on release, a hold
      passes after 18 frames) because holding Select is Ezlo's hint (CanDispEzloMessage).
      The gptokeyb2 `hk_hotkey` layer was not used: it never fired on the device (see below).
- [x] device test of the sp9 build (2026-09-23, local build, launched from the muOS menu):
      Select+Y opens the load page. Select+X froze the game: the fork's raw-pad practice combos
      (Select+X = practice pause, Select+Y = frame step, Select+A/B = load/set practice point)
      read the pad alongside gptokeyb2's keys. Fixed in 3b49d8d13 (off under
      `select_state_chords`), installed as md5 ea032fe6, not yet re-tested. Still open: bare X/Y
      fire assigned items, Select tap still gets Ezlo (one injected tap and one 0.8 s hold showed
      no Ezlo; baseline on sp8 at the same spot not taken), pause-menu Select+A/B assigns.
      Old state files do not load: quicksave format is now v8.
- [x] fast-forward was flat out (526 TPS in the Minish Woods on sp8, ~8.8x); user asked for 25%
      less. Fork `fast_forward_speed` (multiple of normal, 0 = uncapped); package sets 6.5.
- Device lesson: launching from adb with muxfrontend SIGSTOPped, then unmuting sinks with
  `wpctl`, gave a loud hiss the volume keys could not touch. Launch from the menu and only inject
  input over adb (notes/custom-scripts.md in the notes repo).
- [ ] doors: none of the known door fixes explain it (#28/#29/#30/#128 and the Type3 guard were
      already in sp8). Ask joshuarcastillo for a screenshot, the area, ROM region and whether
      entrance shuffle is on.
- [x] push the branch, tag, bump build.sh, cut package v2.3.0: see "Release sp10 / v2.3.0"
      above. The sp9 tag's release build failed (linux arm64 xmake abort) and was never published.
- [ ] reply to NoseDevilEugen and joshuarcastillo

## Native-port features (ideas, 2026-09-23)

Open ones are filed as issues on the fork (issues enabled 2026-09-23, labelled `help wanted`)
so other people can pick them up: https://github.com/lorencouse/tmc/issues

Things an emulator cannot do, or that other handheld ports ship. All of it lives in the fork,
so each one widens the diff against upstream; prefer the ones upstream would take. The SP renders
in software, so anything drawn every frame has to be cheap.

- [~] Check tracker: fork branch `check-tracker` (7ec519216, merged into master via
      sp10-features). A Tracker group in the settings overlay (after Equipment; also a
      ribbon tab), for vanilla play and rando alike: the 228 randomizer locations with collected
      state read from save flags, and the 100 kinstone fusions (not fused / fused, reward waiting /
      done) from `gSave.kinstones`. Nothing is stored beside the save. The fork's existing
      rando-only "HUD Tracker" window sits on the stubbed `RandoLogic_EvaluateReachability`, so its
      Locations list is always empty.
  - Files: `port/port_tracker.{c,h}`, `port/port_tracker_fusions.inc` (generated by
    `tools/gen_tracker_fusions.py`; `*.py` is gitignored in the fork, so `git add -f` it),
    `port/port_repro_tracker.c`; `src/common.c` gains `GetFusionWorldEventId` /
    `CheckFusionEventDone`, factored out of `UpdateVisibleFusionMapMarkers`.
  - Console shell fix on the way: entering a group now resets the body's scroll and puts the nav
    cursor on the group's first widget (`NavInitWindow`). Before, a long group opened at the
    list's scroll offset and the first Down landed part-way down the page.
  - Coverage (first cut; now 224 of 228, see below): 184 of 228 checks tracked. 18 chests resolve through the room's chest list, 137
    ground items / heart pieces / digs through the flag in the key (EU/JP via the baseline flag
    remap), the bell heart piece by its flag, and in vanilla play 28 unique-item gifts by
    inventory. 44 untracked: Goron merchant (15), cucco rounds (10), Stockwell (5), great
    fairies (3), bomb Minish (2), and one each of the Crypt prize, DHC king, Biggoron, Melari,
    cafe lady, dog, scrub bottle, Gregal shells, simulation chest.
  - Verified headless in the bullseye container (`TMC_REPRO_TRACKER=1`, `_UI=1`, `_WARP=1`):
    every open check / fusion flips when its flag or fused bit is set; warping into each
    flag-keyed room finds a live object with that flag for 118 of 132 (the 14 misses are
    fight / pot / statue / kill drops and cutscene gifts that only exist after an event); the
    overlay reaches the page with synthetic D-pad presses, A switches to fusions, A opens a
    header. Generated fusion labels match the runtime world-event areas for all 91 non-gold
    fusions. Not yet seen on the SP screen, and no mid-game save was on hand: the SP's slot 0 is
    a fresh rando file and its old states are sp8 format.
  - [ ] look at it on the SP (640x480 console shell) with a mid-game save
  - [x] fusion names: 18 of 91 still just "Event" (was 46). Types 4-7, 11 and 18 named from
        before/after captures of each fusion's spot (`TMC_REPRO_TRACKER_SHOTS=1`); the generator
        also had to follow the USA `#if` branches of `gWorldEvents` (it was off by the EU/DEMO_JP
        rows).
  - [x] untracked checks: 44 -> 4, from a source read of each reward's flag (Goron merchant =
        highest LV flag + slot sold flags, cucco = ANJU_LV bits / ANJU_HEART, Stockwell SHOP00_*,
        great fairies IZUMI_*, Crypt OUBO_KAKERA, DHC LV6_1d_KEYGET, Biggoron DAIGORON_*, Melari
        broken sword == 2, cafe MACHI_MES_60 (not in open world), dog BIN_DOGFOOD (EU: dog food ==
        2), scrub AKINDO_BOTTLE_SELL, Gregal SORA_ELDER_TALK1ST). Left: Stockwell 300 and dog
        food, Bomb Minish reward 1, Simulation chest -- nothing in the save records them.
  - [x] fusers: under each unfused fusion, who has it on their list (NPC name from the ROM fuser
        tables, area from a one-time scan of room entity lists; 39 of 111 have no area because a
        room function spawns them), "offering now" / "later in the story", or "any fuser at
        random" for the 18 shared ones. All 91 non-gold fusions have a source.
  - [x] old rando "HUD Tracker" Locations tab now lists uncollected checks from port_tracker
        (it filtered on the stubbed reachability and was always empty)
  - [ ] rando hooks that probably never fire (from the same source read, not tested in game): (https://github.com/lorencouse/tmc/issues/10)
        DHC B2 King (script.c keys MINISTER_POTHO + rupee, but King Daltus gives the key),
        Melari (every rando file presets OYAKATA_DEMO, skipping the reward branch), Simulation
        chest (a small chest in a room with no tile-entity list, so no key is built)
  - [ ] the scripted-check rules have no flip test in `port_repro_tracker.c` yet (plain keys do) (https://github.com/lorencouse/tmc/issues/10)
- [ ] Minimap / HUD in the letterbox bars once the zoom-out work (`../picori-zoom`) lands (https://github.com/lorencouse/tmc/issues/1)
- [ ] Suspend on quit / lid close, resume on next launch (quicksave has an engine-resume path) (https://github.com/lorencouse/tmc/issues/2)
- [~] QoL toggles, default off: instant text outside rando done (`instant_text`, fork f804b1a6f, (https://github.com/lorencouse/tmc/issues/3)
      in master). Still open: skip repeat "You got a red rupee!" boxes, shorter fusion / portal /
      shrink animations, skippable cutscenes, faster Pegasus charge
- [ ] Difficulty / cheat sliders on the Reborn flag system: damage multiplier, one-hit KO, (https://github.com/lorencouse/tmc/issues/4)
      bigger wallet, infinite ammo, no fall damage
- [ ] Photo mode: hotkey writes a PNG of the HUD-less frame (https://github.com/lorencouse/tmc/issues/5)
- [x] Tunic / heart colours outside rando: `tunic_color` / `heart_color` (fork f804b1a6f, in master)
- [x] Low-health beep: `low_health_beep` normal / slower / off (fork f804b1a6f, in master)
- [x] Separate music and SFX volume: fork branch `audio-volume-split` (ee3db5fe5, in master). `music_volume` / `sfx_volume` (default 1.0),
      sliders under Master volume. Music = songs on the game's BGM player (index 31), the split
      the game itself uses; item-get fanfare and jingles count as SFX. Headless: 0.5 / 0.25 in
      config gave exactly 0.5 / 0.25 energy per category; runtime_config test extended and run.
- [ ] Button remap page in the overlay (bindings are only editable in config.json / the ini) (https://github.com/lorencouse/tmc/issues/6)
- [~] Battery and clock in the overlay footer: fork branch `overlay-status` (worktree
      `../picori-overlay-status`, off master, uncommitted). Right end of the console shell's
      legend line, "14:05   87%" ("+" while charging); first `/sys/class/power_supply/*` with
      type Battery (axp2202-battery on the SP, checked over adb), re-read every 5 s; clock only
      when there is no battery. Needs a look on the SP screen.
- [ ] Sleep/wake hardening: audio device back, no hiss (see the adb hiss note above) (https://github.com/lorencouse/tmc/issues/7)
- [ ] Achievements: RA is compiled out for want of libcurl; dlopen it when present (https://github.com/lorencouse/tmc/issues/8)
- [ ] A bundled example mod pack and a short how-to, to show the mods system off (https://github.com/lorencouse/muos-rg35xx-sp-picori/issues/2)

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
    - [~] frame rate in a busy area: 55 fps drawn / 60 tps in the Minish Woods with a text box
          up (2026-09-17, sp8, on-screen counter). A longer session still wanted.
    - [ ] audio: device opened 44100 Hz / 1920 frames; listen for dropouts. If it stutters, try
          `echo 4096 > /mnt/mmc/ports/picori/audio_frames` and relaunch
    - [x] save states: verified on the SP 2026-09-10. Mapping settled as L2 = save to a new
          slot, Select+L2 = load (see the Kdog thread below; the load-on-bare-L2 round was
          reverted on request), overlay Saves tab picks the slot.
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
- [x] PR description drafted to the PortMaster template in `docs/portmaster-pr.md`, AI-assisted
      box ticked, every non-standard launcher line explained there.
- [ ] Reply to Cebion on Discord in my own words. Facts to lean on: template launcher, gptokeyb2
      ini, port.json v4, mixv1 cover, sdl3shim instead of weston, source branch cited in README and
      port.json, tested on the SP (muOS). v2.0.0 zip:
      https://github.com/lorencouse/muos-rg35xx-sp-picori/releases/tag/v2.0.2 (v2.0.0 is the
      black-screen build, do not link it)
- [ ] Hand EpicNoob the **v2.2.0** zip for the
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
- [x] v2.1.0 tagged 2026-09-10: fork release `v0.8.3-sp7`. Fixes the blank screen after a
      cross-session save-state load, keeps the settings shell half-screen on every group, and
      swaps the save-state pair to L2 = save / Select+L2 = load. Same shim as v2.0.2.
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
  - [ ] ask EpicNoob to re-test the v2.2.0 zip and send `ports/picori/log.txt`

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
    - [x] fork release `v0.8.3-sp7` cut 2026-09-10 (CI 34502158642, all legs green); build.sh
          repinned (sha 37c00654...) and the arm64 `tmc_pc` pushed to the SP, old binary kept as
          `tmc_pc.aarch64.sp6.bak`. sp7 also carries the split for *every* console group, not
          just Display: stepping with L1/R1 no longer jumps between half the screen and all of
          it. Verified on the SP.
  - [x] save-state picker (fork, needs a CI build and a new tag): full-screen slot page on its own
        binding -- one big preview, timestamp plus relative age, a filmstrip of the neighbours,
        A load / X save here / Y save to a new slot / B close. Opened by `state_menu`
        (keyboard End), which the package puts on **Select+L2**; bare L2 still saves to a new
        slot, and Select+L2 no longer loads blind. Verified on the macOS host build only.
        Shipped in sp8 / package v2.2.0 and verified on the SP 2026-09-17 (see "Where it stands").
    - [x] the reason no preview has ever been visible, here or in the Saves tab: the thumbnail
          code pushed its `ImTextureData` straight into `platform_io.Textures`, which ImGui
          rebuilds every frame from its own atlases plus the *user* list, so the create request
          was wiped before the renderer backend saw it and every slot drew as a white rectangle
          (confirmed on the host: status stuck at WantCreate, TexID 0). Now registered with
          `ImGui::RegisterUserTexture` and drawn with nearest filtering, since the picker scales
          a 120x80 capture up 3-4x.
    - [x] **Select+L2 never fired on the device** (reported 2026-09-10: it just quick-saved, i.e.
          the bare `[controls]` L2 = `home` was used and the `hk_hotkey` layer was not entered).
          The `-d` dump has always shown the layer parsed and `-H back` accepted, so the dump
          proves nothing about a real press; the layer has never been confirmed working with
          hands on any build. Rather than keep debugging gptokeyb2's modifier, the layer and
          `-H back` are gone and the pickers moved to plain buttons.
    - [x] **X = picker ready to save, Y = picker ready to load** (asked for 2026-09-10). Two
          engine actions (`state_menu_save` / `state_menu`, keyboard Insert / End), and inside
          the page the other button switches modes instead of acting -- so coming in the wrong
          door costs one press and can never throw a run away. A is always the mode's action.
          X and Y were the soft equip slots; nothing on this device has ever assigned an item
          to them (no `tmc.softslots` sidecar), and they are still C and V on a keyboard.
          Both modes verified on the macOS host build, including the switch.
    - [x] ini, launcher (no `-H back`) and config pushed to the SP; gptokeyb2 parses
          `x = "insert"` / `y = "end"`, and the port launches and reaches AgbMain with them.
    - [x] device test of the picker itself (2026-09-17, sp8 binary, keys injected over adb):
          Y opens the load page with the real frames in the previews, X switches it to the
          save page, B closes, A on an empty slot toasts, A on slot 2 resumed a Minish Woods
          state (55 fps drawn, 60 tps).
  - [x] fork follow-up (needs a CI build, so not in this zip): make `Port_UiScale()` read
        `SDL_GetCurrentRenderOutputSize` and recompute on `SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED`
        instead of caching the pre-fullscreen window size -- same fix d573de767 applied to the
        boot splash. Consider also whether AUTO should key off "no mouse" rather than window
        width, so a 720p handheld gets the console shell without the package pinning it.
        Done on fork branch `uiscale-output-size` (worktree `../picori-uiscale-output-size`,
        uncommitted): the scale was computed once, inside Port_PPU_Init, from the 240x160
        pre-fullscreen window; now measured from the render output and re-applied on
        WINDOW_PIXEL_SIZE_CHANGED / RESIZED (headless: 0.5 at init -> 1.6 after fullscreen on the
        dummy 1024x768 display). Not tested at exactly 640x480 / 1280x720 or through the shim.
        AUTO left alone; the suggestion is `w <= 860 * Port_UiScale()` (720p handhelds would get
        the console shell unpinned, but so would 960x640 and 1366x768 desktop windows).
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
    - [x] reversed again 2026-09-10 on request: **L2 = save to a new slot, Select+L2 = load**.
          Saving is the press you make mid-play, and keeping load behind the modifier stops a
          stray L2 from throwing progress away. README's controls table follows.
    - [x] blank screen after a state load (SP, 2026-09-10): loading a state written by an
          *earlier run* left the picture stuck at the last fade's colour while the room, its
          palettes and the music ran on behind it; pressing Start brought it back because the
          pause menu re-flags every palette. Cross-session loads resume through the engine, and
          room init *inverts* the standing fade rather than setting one, so arriving from live
          gameplay (a finished fade-in) inverted into a fade-*out*. Fork fix in sp7: fade out to
          black before `SetTask(TASK_GAME)`. Verified on the SP.
    - [ ] superseded, kept for the PR discussion: that L2 loads and Select+L2 saves a new slot,
          that a Select *tap* still reaches the game (the dump cannot show what gptokeyb2 does
          with the modifier on release), and that holding Select does not mute the face buttons
          or the F8 overlay
  - [x] menu button differs per device (Menu on the Pro S, R3 on the R36S): that is the firmware's
        Guide mapping, nothing to change in the package. Noted in the port README's controls table.

- RG35XX Plus / muOS Pixie (joshuarcastillo, 2026-09-16, v2.0.2): "unable to create save file".
  The card is full, and the port is what filled it. Three lines in his log are the same fault:
  `[quicksave] short write state_auto_0.bin (4064/665836)`, `[SAVE] ERROR: atomic write of
  tmc.sav failed`, and `assets_src/usa/texts.json` parsing as "unexpected end of input" (an
  empty file, i.e. a write that was cut off). He then reports `ports/picori` sitting at 5.1 GB.
  - [x] root cause, measured on the host 2026-09-17: `runtime_only` in the extractor only
        *deleted* `assets_src/` after a successful run; the tree was still written in full
        first. That tree is 121 MB in 24,127 files. On a large exFAT card (128 KB clusters on
        64 GB and up) that is about 3 GB of cluster slack, plus `rom_data/` (2,789 four-KB
        files, ~350 MB the same way), which is the 5.1 GB. His extraction was interrupted (the
        log ends in `Killed`, the launcher's Start+Select path) so the tree never got deleted,
        and the next launch found the truncated `texts.json`.
  - [x] fork (`rg35xx-sp-audio-ui`, uncommitted 2026-09-17, needs a CI build and an sp8 tag):
        `runtime_only` now really skips the editable tree. Every low-level writer
        (`write_binary_file`, `write_text_buffered`, `BackgroundWriter::Submit`,
        `PortAssetPipeline::Write*`) treats a path under a registered root as already written
        (`PortAssetLog::SetSuppressedWriteRoot`), and a stale `assets_src/<region>` is wiped
        before extraction starts. Host check: the nine paks and eleven JSONs are byte-identical
        to a run that wrote the editable tree, 0.4 s instead of 2.4 s, no `assets_src/` left.
  - [x] a leftover `assets_src/` no longer bricks assets: `EnsureAssetGroupCache` falls back
        to `FindRuntimeAssetsRoot()` when the rebuild fails and logs `[ASSET] Ignoring ...;
        using the existing runtime assets`. Verified headless on the host with a truncated
        `texts.json` next to a complete `assets/usa`: the game reaches AgbMain.
  - [x] `[SAVE] ERROR` and `[quicksave] short write` now print `strerror(errno)`, so "No space
        left on device" is in the log. The quicksave also checks `fclose` (where ENOSPC surfaces
        for a buffered write) and removes the truncated slot file.
  - [x] all three verified on the SP 2026-09-17 with a local aarch64 build (see
        `tools/bullseye-arm64.Dockerfile`; binary md5 8dc11569, kept as
        `.cache/tmc_pc-local-sp8-8dc11569`, the sp7 binary is `tmc_pc.aarch64.sp7.bak` on the
        device): a seeded truncated `assets_src/usa` next to a good `assets/usa` logs the
        `[ASSET] Ignoring` line and boots; with `assets/` removed the cold extraction takes
        9.6 s (was about two minutes), leaves no `assets_src/`, and the title screen draws.
  - [ ] reply: his fix today is to free space, then `rm -rf ports/picori/assets_src` (or just
        wait for the next zip, which does that itself); first launch re-extracts in about two
        minutes. Ask for `du -sh /mnt/sdcard/ports/picori/*` only if the folder is still large
        after that, since `rom_data/` alone is a few hundred MB on a 128 KB-cluster card.
  - [ ] `rom_data/`: 2,789 loose 4 KB pages is the wrong shape for an SD card for the same (https://github.com/lorencouse/tmc/issues/9)
        reason. Pack them into one file (or read straight from `baserom.gba`, which is sitting
        next to it) in a later cut.

- R36S / DARKOSRE (CrispTheBunz, 2026-09-16): runs, but segfaults, "mainly during boot".
  - [ ] untested CFW and untested device. Ask for `ports/picori/log.txt` and the
        `bugreport_*` folder the crash handler writes next to the binary (`backtrace.txt` is
        the one that matters), and which zip. Nothing to guess at until then: the R36S on
        AmberELEC runs (Kdog, above), so this is DARKOSRE or its SDL, not the device.

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
- [x] The file-select screen opens the fork's "Port & Randomizer Setup" sidebar on its own
      (seen on the sp6 run with no input). Check whether that is meant to be on by default on a
      handheld; "Close Sidebar" dismisses it.
      It does not open on its own: only an L press on file select toggles it (L1 = 'a' on the
      SP, so a stray touch), and it stayed shut ~100 s headless with no input. But once open, B
      and the D-pad did nothing in the console shell, so only a second L closed it. Fork branch
      `fileselect-sidebar` (worktree `../picori-fileselect-sidebar`, uncommitted): port_bios.c
      feeds the sidebar's key events through the console nav translation; headless B now closes
      it, desktop unchanged.
- [ ] Autosave: with `autosave_enabled` the game writes a 650 KB ring slot every 60 s to the SD
      card (three slots). Harmless so far; watch for hitching on the interval.
