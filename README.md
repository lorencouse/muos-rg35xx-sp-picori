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
unlikely to run this binary at all.

## Status

Tier A: installable. Not yet submitted to PortMaster.

- [x] Launcher hardened with trap-based teardown (governor + PipeWire settings
      are system-wide; a crash previously left them applied until reboot)
- [x] Game runs backgrounded under `wait` so signals are not deferred
- [x] ROM presence + SHA-1 validation across all three regions
- [x] First-launch asset-extraction notice (~2 min on a still screen)
- [x] `port.json` / `gameinfo.xml` / player README
- [x] `screenshot.png` (captured from the device) and `cover.png`
- [x] Tagged release [`v0.8.3-sp1`](https://github.com/lorencouse/tmc/releases/tag/v0.8.3-sp1)
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
