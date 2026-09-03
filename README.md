# muos-rg35xx-sp-picori

Packaging for **Project Picori** (*The Legend of Zelda: The Minish Cap* PC port)
as an installable port for the Anbernic RG35XX SP running muOS.

The player-facing documentation is [`port/picori/README.md`](port/picori/README.md).
This file is about building the package.

## Build

```sh
./build.sh 1.0.0            # -> dist/picori-1.0.0.zip
```

`build.sh` fetches the `tmc_pc` binary from a tagged release on the fork,
verifies it against a pinned SHA-256, stages `port/` around it and zips the
result. The 59 MB binary is deliberately not in git.

To build against a local compile instead:

```sh
TMC_BINARY=/path/to/tmc_pc ./build.sh 1.0.0-dev
```

## Test

```sh
./tools/test-launcher.sh
```

Runs the launcher against a sandboxed PortMaster/sysfs/weston/PipeWire stub and
asserts that the CPU governor and the forced PipeWire clock are restored on all
three exit paths (missing ROM, clean quit, killed mid-game). Both of those are
system-wide settings, so a teardown bug misconfigures the device until reboot;
this suite caught exactly that twice. Run it after touching the launcher.

## Layout

The zip unpacks into `ports/`, following PortMaster convention:

```
Legend of Zelda - The Minish Cap.sh    launcher
picori/
  tmc_pc                  fetched at build time, not in git
  config.json             port settings (device-tuned defaults)
  tmc_pc.gptk             pad -> virtual keyboard map
  picori-weston.ini       320x240 X screen, 2x compositor upscale
  port.json               PortMaster metadata
  gameinfo.xml            frontend metadata
  README.md               player documentation
  version.txt             stamped by build.sh
  baserom.gba             SUPPLIED BY THE USER, never shipped
```

## Where the binary comes from

Upstream is [999sian/tmc](https://github.com/999sian/tmc) (GPL-3.0-or-later).
The shipped build is the fork
[lorencouse/tmc @ `rg35xx-sp-audio-ui`](https://github.com/lorencouse/tmc/tree/rg35xx-sp-audio-ui),
five commits ahead of `master`, all of them handheld-class fixes:

| Commit | What |
|--------|------|
| LINEAR resampler | Upstream's SINC resampler costs a whole A53 core here — music played at half speed |
| 44.1 kHz synth | The SP codec's "48000" clock runs fast; 44.1 kHz is the honest rate |
| `TMC_UI_SCALE` | The ImGui overlay is fixed 380–620 px wide, off-screen on a 320 px display |
| `aspect_mode: "stretch"` | Fill a 4:3 panel instead of letterboxing the native 3:2 frame |
| `aspect_mode: "pixel_perfect"` | Integer scaling — every game pixel becomes an identical NxN block |
| `TMC_AUDIO_TRACE` | Logs frames/s pulled and the negotiated device format |

None of these are SP-specific hacks, so the intent is to upstream them and go
back to shipping official release builds. Until then this repo pins a fork tag.

## Picture quality

Two independent defects were measured on the panel and fixed:

1. **The compositor was blurring everything.** At weston `scale=2` the X screen
   is 320x240 and weston bilinear-upscales it to the 640x480 panel. Captured
   from `/dev/fb0`: **0 of 320** column pairs identical, and one scanline
   carried **326 distinct colours** from a 320px source. `scale=1` makes the X
   screen match the panel, so weston composites 1:1 and filters nothing —
   the same capture then gives 110/320 identical column pairs and 21 colours.
2. **Nothing scaled by an integer.** Every mode was fractional: 1.3333x/1.5x
   under stretch, so nearest-neighbour produced source pixels of *different
   widths* (a repeating 2,1,1). `pixel_perfect` (added in v0.8.3-sp2) snaps to
   the largest whole multiple.

The cost, measured in real decoupled play on the same scene:

| | `present` | fps | tps |
|---|---|---|---|
| `scale=2` (old) | 3.24 ms | ~30 | 60.00 |
| `scale=1` (now) | 7.5 ms | ~26.5 | 60.00 |

The X socket has no MIT-SHM, so the whole window is copied every frame and the
transfer dominates — which is why pixel-perfect saves less than its pixel count
suggests (15.4 vs 19.1 ms on the bench). **Game speed is unaffected either way**;
only the render cadence moves. Those `fps` figures are pre-v1.2.0; see below.

## Frame rate

The port now holds **60 fps**. It used to run at 30, and both halves of that
were self-inflicted:

1. **`frame_time_ns` was 33333333** — a 30 fps render cadence, written into the
   shipped `config.json`. Under decoupled pacing this caps only the render
   grid, so the game was always *ticking* at 60; it just drew every other tick.
2. **Raising the cap alone made it worse, not better** (~14 fps). The decoupled
   pacer only presents when `now + presentCostEMA <= tickDeadline`. A present
   cost ~16.5 ms against a 16.67 ms tick window, so the fit test failed every
   time and frames only went out on the 100 ms starvation override. Skipped
   presents keep the EMA high, which skips more — a death spiral.

The fix is `internal_scale: 2`, which is counter-intuitive: it does *more*
work and runs faster. SDL's software renderer scales 240x160 -> 640x480 (2.67x)
far more slowly per output pixel than 480x320 -> 640x480 (1.33x). Pre-expanding
2x in the port's own tight loop costs ~3.7 ms of render but takes the whole
present from 16.5 ms to ~8.7 ms — comfortably inside the tick window, so every
tick presents.

Measured on device, 45-90 s runs, governor pinned, frontend stopped:

| `frame_time_ns` | `internal_scale` | `present`/present | presents per 120 ticks | fps |
|---|---|---|---|---|
| 33333333 (30) | 1 | 16.5 ms | 60 | 30.0 |
| 16666667 (60) | 1 | 16.5 ms | 29 | ~14 |
| 20000000 (50) | 1 | 16.3 ms | 36 | ~18 |
| 16666667 (60) | 4 | 20+ ms | 18 | ~10 |
| **16666667 (60)** | **2** | **8.7 ms** | **120** | **60.00** |

Over a 90 s run: 82 of 85 samples at exactly 60.00 fps, 2 at 59.02, 1 at 58.03,
zero audio underruns, ~40% of the four cores total (game 21%, weston 13%,
Xwayland 9%).

**The prescale is pixel-identical, not a quality trade.** Both paths are
nearest, and `floor(floor(x*480/640)/2) == floor(x*240/640)` for all x because
`floor(floor(y)/n) == floor(y/n)` for positive integer n; vertically both
reduce to `floor(y/3)`. Pixel-perfect becomes a straight 1:1 blit. `4` is past
the sweet spot — the 960x640 intermediate costs more than the cheaper blit
saves.

### Follow-up (2026-09-03): the 60 was partly luck, and where the time really goes

A later report of "dropping a lot of frames" led to a full pacing study with
the port's profiler, the muOS frontend stopped and the governor pinned. The
same binary and config measured 37-57 fps on one launch and 12-15 on the next,
and every run eventually fell into a regime of ~8 fps. What was found:

- **The panel is 640x480 @ 59.98 Hz** (framebuffer driver), but the crusty
  fake-DRM layer that weston runs on reports **66.8 Hz**. SDL's software
  renderer has no real vsync: it sleeps to a timer at the *reported* rate
  after each copy. A weston `mode=` line can force 59.9 or 120 Hz and the
  shim accepts it, but the custom-mode path presented *slower* (18 ms per
  present) than the native one, so the shipped config keeps the native mode.
- **Per present, in motion:** ~4.5 ms raster + 2x prescale, 0.3 ms texture
  upload, ~5 ms for the X copy. With a 5-7 ms game tick that is 15-17 ms per
  frame against a 16.67 ms budget — 60 fps only in light scenes.
- **The X copy is the variable.** It costs ~5 ms while frames stream and
  ~17 ms after the compositor has gone idle (a static screen, or a run of
  skipped presents). The pacer's cost-fit check then refused the next
  present too, which made the following one dearer: a spiral down to the
  100 ms starvation floor. Fork `v0.8.3-sp3` caps consecutive skips at two.
- **Vsync-locked ticks** (present every tick, re-seat the grid on the
  return) were tried and measured: they serialise the copy with the game
  and dropped game speed to ~50 ticks/s here. The feature is in the fork as
  an opt-in (`vsync_lock_ticks`, off) because it is right where a present
  genuinely blocks on a refresh.
- **Fast-forward** was bounded by presenting at 60 Hz: a tick that does not
  present skips the raster too and costs ~2.3 ms, so `fast_forward_fps: 15`
  took R2 from ~2x to **5-7x** (306-415 ticks/s measured).

### The present thread (built, not yet measured here)

What fixes normal play properly is a **present thread**: the X copy blocks the
game thread for 5-17 ms, and nothing in pacing can hide that. That now exists
in the fork as `present_thread` (`config.json`, default off;
`TMC_PRESENT_THREAD=1` overrides for one session).

The game thread rasters and prescales as before, hands the finished pixels to
a worker and returns; the worker owns the texture and does upload -> clear ->
compose -> present. Handoff is latest-wins over two staging buffers, so the
engine never blocks on the display and a slow present costs display rate,
never game speed. The pacer needs no changes: its present-cost EMA measures
what the game thread actually pays, which is now a memcpy, so the cost-fit
check that was refusing presents starts passing on its own.

Overlays are the catch. The settings menu, soft slots and touch controls draw
through the same renderer *and* read live game state, so they can never run on
the worker. The ImGui frame is therefore built first — that touches no
renderer — and whether it produced any draw data picks the path: an empty draw
list (normal gameplay in console mode) presents threaded, anything else drains
the worker and presents synchronously as before.

Measured on the SP, launcher-driven, 95 s runs, same scene, same binary.
Statistics are over the 85 in-run samples, excluding the teardown tail:

| CPU | `present_thread` | fps mean | fps min | present (game thread) | tps |
|---|---|---|---:|---|---|
| 1.512 GHz | off | 59.70 | 55.08 | 8.92 ms (raster 4.7 + flip 4.1) | 60.01 |
| 1.512 GHz | **on** | 59.44 | 55.08 | **6.15 ms** (flip 0) | 60.01 |
| 1.200 GHz | off | 57.85 | **40.33** | ~9.5 ms | 60.01 |
| 1.200 GHz | **on** | **59.78** | **57.05** | ~5.2 ms | 60.01 |

**At full clock this scene has headroom, so the frame rate does not move** —
the flip simply stops being the game thread's problem, worth ~2.8 ms/frame.
The handoff is not free: it copies the finished 480x320 frame into staging,
which is why the raster column absorbs part of what the flip column gives up.

The bottom two rows are the point. Underclocking to 1.2 GHz puts the same
scene over budget, which is the condition the port actually cares about, and
there the saved time converts into frames: **the worst second goes from 40.3
to 57.1 fps** and the mean recovers to within a frame of 60. The gain is in
the floor, not the average — which is what "drops frames in busy scenes"
means to a player.

Game speed (`tps`) is 60.01 in every configuration; decoupled pacing was
already protecting that. What changes is whether the display keeps up.

The per-second census (`TMC_PACE_LOG=1`) reports 61 of 61 presents threaded
with zero fallbacks to synchronous, so the overlay check is not quietly
disabling the path.

### Two measurement traps, both hit while producing the table above

- **Not every launch brings up the same backend.** One run showed
  `fps mean=30.95`, which read as a catastrophic baseline. It had no
  `PPU: SDL_Renderer driver = ...` line at all: `SDL_CreateGPUDevice` failed
  *and* the SDL_Renderer failed, so it silently fell back to the surface
  path. Its present census was all zeros, which is the tell. Any run used for
  comparison has to be gated on the backend line and a non-zero census first.
- **Tearing weston down with `kill -9` poisons the next launch.** Runs that
  followed a `pkill -9 weston` measured `flip=70 ms` and `tps=29` on *both*
  settings — a half-torn-down compositor makes the X copy roughly fifteen
  times more expensive. Let the launcher's own `cleanup()` run and give it
  time; every run from a clean state reads as the table.

Both of these produce numbers that look like real findings, so they are
recorded here rather than quietly fixed.

Dead ends, ruled out by measurement rather than guessed at:

- **Native Wayland** (drop Xwayland): the shipped SDL3 prints
  `SDL compiled video drivers: x11 kmsdrm offscreen dummy evdev` — no Wayland
  driver is built in, so this needs a fork rebuild.
- **MIT-SHM**: `ipcs -m` says *kernel not configured for shared memory* and
  there is no `/proc/sysvipc`. Genuinely impossible, not a config miss.
- **Hardware blit** via westonwrap's `crusty_x11egl` gfx mode: EGL comes up
  (`GL version: OpenGL ES 3.2`) but SDL still reports
  `SDL_Renderer driver = software` and `SDL_CreateGPUDevice failed`. No gain.
- **`vsync: false`**: made it *worse* (~8 fps). Present blocks ~16 ms either
  way, and turning vsync off only removed the pacing that was keeping the EMA
  honest.

## Shutdown

Until v1.2.1 every quit ended in `SIGABRT` and left a ~900 KB `bugreport_*`
directory in the port folder. Not a game bug — a launcher ordering bug.

`GAME_PID` is the pid of `westonwrap.sh`, not of `tmc_pc`. Signalling the
wrapper tore weston down (and Xwayland with it) while the game was still
attached to the display, so inside `tmc_pc`:

```
X connection to :0 broken (explicit kill or server shutdown).
free(): corrupted unsorted chunks
[BUG] CRASH (SIGABRT)
```

libX11's default IO error handler ran on a display that had already gone
away, and glibc tripped over the heap on the way out. The captured state was
worthless too (`Area 0x0`, `HP 0/0`, `Frame 0`) because it was teardown, not
gameplay — so the bug reporter only ever produced noise.

The fix is ordering: `cleanup()` now finds `tmc_pc` by name, sends it
`SIGTERM`, waits up to 5 s for it to actually be gone, and only then
terminates the wrapper. Verified on hardware — clean exit, no `SIGABRT`, no
bugreport bundle, no survivors, governor back to `ondemand`.

This also corrects a note that stood since the 60 fps work: `tmc_pc` *does*
exit on `SIGTERM`. It had simply never been sent one.

**Still open (fork-side, not fixable here):** the game does not flush a save
when it exits. Progress falls back to the interval autosave ring, so the
worst case is bounded rather than lost, but a save-on-`SIGTERM` handler in
`999sian/tmc` would close it.

## Save states

Twenty manual slots plus a three-deep auto-save ring, all in **MENU → Saves**.
One manual slot is *selected*; that is what the load button restores, and the
selection persists in `config.json` as `savestate_slot`.

| Button | Action |
|---|---|
| **L2** | Quick-save to a new slot (counts up, wraps at 20) |
| **R2** (hold) | Fast-forward |
| **Y** | Load the selected slot |
| **SELECT + L2 / R2** | Previous / next slot |

The picker shows a **preview thumbnail** and a timestamp per slot. Twenty
identical dates would tell you nothing about which state is the fight you
wanted, so each save captures the frame that was on screen.

Within a session a load is exact. A state from an **earlier session** restores
the save file and re-enters the same room at the same position through the
game's own continue path (toast: "room re-entered"): inventory, flags, health
and position carry over, room state starts fresh. See below for why.

### What had to change in the fork

Save states existed but every route to them was a hard-wired keyboard case —
F5/F6 quick, F1-F4 direct. There is no keyboard on this device, so the only
way in was the F8 menu, and the Controls tab, which rebinds every other
action, had nothing to offer. Fast-forward was TAB-only for the same reason.

Six bindable actions now exist — `state_save`, `state_save_new_slot`,
`state_load`, `state_next_slot`, `state_prev_slot` and `fast_forward` — acting
on a selected slot rather than a fixed one, so a handful of binds reach all
twenty. Thumbnails ride in a `state_N.thumb` sidecar rather than inside the
state file so that adding them did not by itself force a format bump. A state
with no sidecar simply shows no picture.

The first on-device test then found the real bug: **a mid-game load stranded
Link off-screen with controls dead.** The upstream snapshot covered the four
GBA memory arrays plus a hand-picked few structs, but this port moved nearly
all of the GBA's RAM residents into host globals — the entity list heads,
entity counters, textbox system, area/room variables, fade, priority handler
and script contexts were all outside it, so a load restored entity bodies from
one moment and bookkeeping from another. The region table now lives beside the
globals (`gPortStateRegions`, 97 regions) and covers everything mutable; a
900-frame headless replay after restore is byte-identical. That did force the
format bump: states from before 1.3.0 show as empty.

Cross-session loads were a second, pre-existing problem: the snapshot is full
of host pointers (entity links, script contexts, the text cursor into an asset
buffer) valid only in the process that wrote them, and relocating them all
means chasing hundreds of heap allocations in the asset loader. Rather than
ship a heuristic, a state carries its writer's session id; a foreign state
restores the save file and re-enters the room through the engine's own
continue path. Exact cross-session restores would need the asset cache moved
to a fixed-address arena — a follow-up, not a blocker.

### What had to change here

SDL sees no gamepad on this device (weston/libinput refuses muOS-Keys, so
gptokeyb hands the port a virtual keyboard). The port can therefore only bind
*keys* — and the SP's buttons send a fixed set of them. Two facts made the
layout work:

- **X, Y, L2 and R2 were free.** They are the port's soft-slot buttons, but no
  `tmc.softslots` sidecar has ever been written, so nothing was assigned to
  them. Y, L2 and R2 now carry the save-state and fast-forward keys; X stays
  free for soft slots.
- **The button names are scrambled.** muOS-Keys reports the pad under borrowed
  key codes, so SDL's `l2`/`r2` are the case's L2/R2 but SDL's `back`/`start`/
  `guide` are SELECT/START/MENU. Decoded from `/proc/bus/input/devices`
  against the launcher's `SDL_GAMECONTROLLERCONFIG`; the table is in
  `tmc_pc.gptk`. There is no `BTN_TR2`, `BTN_MODE` or `BTN_THUMBL/R` in the
  key bitmap at all — the SP has no sticks and no spare button beyond those.

Slot cycling needs a modifier, and the spare keys for it come from a gptokeyb
hotkey layer: `[controls:hk_hotkey]`, activated by `-H back` on the gptokeyb
command line, remaps L2/R2 while SELECT is held.

Two things worth knowing if you edit that layer:

- A key **left out of a layer is unbound while the hotkey is held**, not
  inherited from `[controls]`. `gptokeyb2 -d` prints it empty. Everything
  that is not an override is therefore repeated verbatim, or holding SELECT
  would also mute the face buttons, START and the MENU overlay.
- `hotkey =` is **not** a `[config]` key. It is the `-H` command-line option;
  the parser prints "unknown global hotkey" and carries on without it.

The auto ring (slots 21-23) is loadable from the menu but not selectable — it
overwrites itself on a schedule, so a hand-made state parked there would
silently vanish.

## Runtime requirements

Determined by reading the ELF directly:

- **glibc ≥ 2.34**, `libstdc++` with `GLIBCXX_3.4.30` (GCC 12)
- Dynamic deps: `libpng16`, `libEGL`, `libGLESv2`, `libgomp`, `libstdc++`
- SDL3 is statically linked — which is *why* the launcher must use westonwrap
  gfxmode `system`: crusty hooks any binary exporting SDL symbols as if it
  were SDL2 and crashes this one.
- PortMaster runtime `weston_pkg_0.2.squashfs`
- PipeWire (the launcher forces `clock.force-rate 44100` / `force-quantum 768`
  on the system graph for the session, and restores them on exit)

That glibc floor is higher than any port currently in PortMaster's catalogue
(the highest `min_glibc` across its 1,422 entries is 2.32), so older CFW are
unlikely to run this binary at all. Confirmed by reading the shipped
`v0.8.3-sp3` binary directly:

```
$ objdump -p tmc_pc | grep NEEDED
  libpng16.so.16  libEGL.so.1  libGLESv2.so.2  libstdc++.so.6
  libm.so.6  libgomp.so.1  libgcc_s.so.1  libc.so.6  ld-linux-aarch64.so.1
$ objdump -T tmc_pc | grep -oE 'GLIBC_[0-9.]+'   | sort -uV | tail -1  -> GLIBC_2.34
$ objdump -T tmc_pc | grep -oE 'GLIBCXX_[0-9.]+' | sort -uV | tail -1  -> GLIBCXX_3.4.30
```

## Device support

The port was written for, and every measurement in this file was taken on,
the RG35XX SP. Nothing in it is *conceptually* SP-specific though — it is a
software-rendered aarch64 binary under the stock PortMaster weston runtime —
so the work in flight is to widen it to the rest of the aarch64 handhelds
without giving up the tuning that made 60 fps reachable here.

Three things gated that, in order of how many devices each one costs.

**1. The runtime ABI floor.** The single biggest one, and it is decided
entirely by the build container: nothing else matters if the loader refuses
the binary. The fork now links `-static-libstdc++ -static-libgcc` on Linux
(`xmake.lua`), which removes the `GLIBCXX_3.4.30` requirement outright, and
builds its aarch64 leg inside `debian:bullseye` (glibc 2.31) rather than on
`ubuntu-22.04-arm` (2.35). bullseye's stock GCC 10 is enough — the only
C++20 in the tree is `<span>` and `<numbers>`, so no LLVM backport is
needed. CI gates the result: `_build.yaml`'s "Report the runtime ABI floor"
step reads the produced ELF and fails the build if it needs anything above
`matrix.glibc_max`, so the floor cannot drift back up unnoticed.

`libgomp.so.1` is still a dynamic dependency (the OpenMP scanline workers)
and is *not* covered by those flags. It is present on muOS; whether every
target CFW ships it is unverified. The ABI step prints the `NEEDED` list on
every build, so this stays visible.

**2. The panel.** `config.json`'s `aspect_mode` and `internal_scale` were
tuned for one 4:3 640x480 screen. The launcher now derives them from the
actual panel — `DISPLAY_WIDTH`/`DISPLAY_HEIGHT` where PortMaster exports
them, else `/sys/class/graphics/fb0/virtual_size`, else the SP's — and
seeds them **once**, on first launch, so a player's own Settings changes
are never overwritten:

| Panel | `aspect_mode` | `internal_scale` | Why |
|---|---|---|---|
| 4:3, ≥480 wide (SP, RG40XX, RG353) | `stretch` | 2 | The measured SP config |
| 4:3, <480 wide | `stretch` | 1 | Too narrow for the 480x320 prescale to pay |
| 1:1 (RGB30, CubeXX) | `pixel_perfect` | 2 | 3:2 stretched to square is grotesque |
| 16:9 (TrimUI Smart Pro class) | `pixel_perfect` | 2 | Likewise |

`weston.ini` is generated at launch too. The shipped `picori-weston.ini`
names the SP's output (`VGA-0`), and weston silently ignores an `[output]`
section matching no real output — so on a device that calls its panel
something else the section was simply inert. The generated file repeats the
same `scale=1` block under every name these handhelds use; at most one
matches and the rest cost nothing.

**3. muOS-only audio.** `SDL_AUDIODRIVER=pipewire` and the forced
`clock.force-rate 44100` / `clock.force-quantum 768` are measured against
*this* codec on a CFW that runs PipeWire. ArkOS and friends run bare ALSA or
PulseAudio, where `pw-metadata` does not exist and naming the pipewire
driver leaves the port silent. The launcher now probes for a live graph and
only takes that path when there is one; otherwise it passes no driver at all
and lets SDL's own probe decide.

### What is still unverified

Honesty about the limits of the above: **it has been tested on the SP and in
the sandbox, not on a second device.** `tools/test-launcher.sh` covers the
panel matrix, the first-launch-only seeding, the generated `weston.ini` and
both audio paths, but a sandbox cannot tell you whether the game is playable.

Two things in particular need someone with other hardware:

- **Input doubling.** All input arrives as a virtual keyboard because SDL
  sees no gamepad on the SP (weston's libinput refuses muOS-Keys). On a
  device where SDL *does* enumerate the pad, `config.json` binds both
  `SDLK:` and `SDL_GAMEPAD:` for every action, so presses arrive twice.
  Harmless for movement; it breaks the held-SELECT hotkey layer, which is
  the only source of spare keys for the save-state actions.
- **CPU headroom.** RK3326 devices (RG351, RG353, OGA) are 4x A35 at
  1.3 GHz — slower per clock than the SP's A53 at 1.512 GHz — so the 60 fps
  cap that `internal_scale: 2` makes reachable here probably is not
  reachable there. The port's own Settings menu is the escape hatch, but
  the shipped defaults for that tier are a guess until measured.

Out of scope: **armhf**. The fork releases an arm64 asset only, and the
32-bit-only devices (RG350, RS97, PocketGo) could not hold the tick rate for
a software PPU regardless.

## Status

Tier A: installable. Not yet submitted to PortMaster.

- [x] Launcher hardened with trap-based teardown (governor + PipeWire settings
      are system-wide; a crash previously left them applied until reboot)
- [x] Game runs backgrounded under `wait` so signals are not deferred
- [x] ROM presence + SHA-1 validation across all three regions
- [x] First-launch asset-extraction notice (~2 min on a still screen)
- [x] `port.json` / `gameinfo.xml` / player README
- [x] `screenshot.png` (captured from the device) and `cover.png`
- [x] Tagged release [`v0.8.3-sp3`](https://github.com/lorencouse/tmc/releases/tag/v0.8.3-sp3)
      on the fork; `build.sh` fetches and verifies from it
- [x] Reproducible build verified from a fresh clone
- [x] Shipped configs verified byte-identical to the working device install
- [x] Launcher verified on hardware (governor pinned + restored, audio thread
      lifted to SCHED_FIFO, frontend hands off cleanly)
- [x] End-to-end install test from the zip on a clean install: extracted
      `picori-1.2.0.zip` into a bare `ports/picori`, supplied only
      `baserom.gba`, and launched. Asset extraction ran from scratch
      (~2 min), the game reached gameplay at a steady 60 fps, and the
      teardown restored the governor to `ondemand` with no stray
      processes. The no-ROM path was checked too: it prints both
      `pm_message` lines and exits 0.
- [x] Shutdown `SIGABRT` fixed — `cleanup()` reaps `tmc_pc` before tearing
      down weston, so quitting no longer aborts inside libX11's IO error
      handler or writes a `bugreport_*` bundle (see **Shutdown**)
- [x] Save-state management: 20 manual slots + auto ring with preview
      thumbnails and timestamps in **MENU → Saves**, driven by L2 (save to a
      new slot), Y (load) and R2 (fast-forward) (see **Save states**)
- [x] Portability pass for devices other than the SP: static libstdc++ and a
      glibc-2.31 build container in the fork with a CI gate on the resulting
      ABI floor; panel-derived `aspect_mode`/`internal_scale` seeded once on
      first launch; a generated `weston.ini` that is not tied to one output
      name; the PipeWire path taken only where a graph answers. Covered by
      20 new checks in `tools/test-launcher.sh` (see **Device support**)
- [ ] Rebuild and retag the fork from the bullseye container, then update
      `build.sh`'s `TMC_TAG`/`TMC_SHA256` and drop `port.json`'s `min_glibc`
      from 2.34 to whatever the ABI step reports. **The binary shipped today
      is still the 2.34 one** — none of the above widens the device list
      until that retag happens
- [ ] Confirm on one non-SP device: input doubling where SDL sees a real
      gamepad, and whether the RK3326 tier needs different shipped defaults
- [ ] PortMaster submission → **Multiverse**
      ([PortsMaster-MV/PortMaster-MV-New](https://github.com/PortsMaster-MV/PortMaster-MV-New)),
      not the main repo: every Nintendo-decomp port (Ship of Harkinian,
      sm64coopdx, zelda3) lives there.

Note for anyone benchmarking: launching the port over adb (rather than from
the muOS Ports menu) leaves `muxplore` running. It keeps drawing to `/dev/fb0`
and keeps `/dev/input/event1` open — the same device gptokeyb2 reads — so the
screen double-draws and every button press reaches both the game and the muOS
menu. That is not a port bug; launch from the Ports menu.

Known cosmetic gaps, from the device log: `SDL_CreateGPUDevice` fails and the
port falls back to software rendering, and no TTS backend exists — so
`gpu_raster` and `tts_enabled` in the shipped `config.json` are inert here.

## Licence

The port binary is GPL-3.0-or-later (Project Picori). The launcher and
packaging in this repo are released under the same terms — see `LICENSE`.

No game data is included or distributed. *The Legend of Zelda: The Minish Cap*
is property of Nintendo.
