# The Legend of Zelda: The Minish Cap — Project Picori

A native port of *The Legend of Zelda: The Minish Cap*, built on
[Project Picori](https://github.com/999sian/tmc) over the
[zeldaret/tmc](https://github.com/zeldaret/tmc) decompilation.

**No ROM is included.** You must supply your own copy of the game.

## Install

1. Install the port (PortMaster, or unzip into `ports/`).
2. Copy your Minish Cap ROM into `ports/picori/` as **`baserom.gba`**.
3. Launch **Legend of Zelda - The Minish Cap** from your Ports list.

Any one of the three regions works — the binary detects which you have:

| Region | Filename         | SHA-1                                      |
|--------|------------------|--------------------------------------------|
| USA    | `baserom.gba`    | `b4bd50e4131b027c334547b4524e2dbbd4227130` |
| EU     | `baserom_eu.gba` | `cff199b36ff173fb6faf152653d1bccf87c26fb7` |
| JP     | `baserom_jp.gba` | `6c5404a1effb17f481f352181d0f1c61a2765c5d` |

**The first launch takes about two minutes** while the game unpacks its assets
from the ROM. The screen sits completely still during this — it has not
crashed. Later launches start normally.

## Controls

The device pad is translated to a virtual keyboard by gptokeyb2 (`tmc_pc.gptk`),
because weston's libinput refuses muOS-Keys outright. The map mirrors
`config.json`'s bindings one-for-one:

| Button   | Game        | Notes                                    |
|----------|-------------|------------------------------------------|
| A        | A           | Sword / confirm                          |
| B        | B           | Item / cancel                            |
| L1       | L           | GBA L                                    |
| R1       | R           | GBA R                                    |
| X        | soft slot   | Extra item slot, assigned in the pause menu |
| Y, L2, R2 | save states / fast-forward | See below               |
| D-pad    | D-pad       |                                          |
| START    | Start       | Pause menu                               |
| SELECT   | Select      | Also the save-state modifier — see below |
| MENU     | F8          | Port settings overlay                    |

### Save states and fast-forward

| Button | Action |
|---|---|
| **L2** | Quick-save to a new slot |
| **R2** (hold) | Fast-forward |
| **Y** | Load the selected slot |
| SELECT + L2 / R2 | Previous / next slot |

**L2 counts up.** Each press saves to the next slot, so a run of presses
leaves a rolling history instead of overwriting one state. There are **20**
manual slots; after slot 20 it wraps back to slot 1 and starts overwriting the
oldest.

**Pick what to load in the settings overlay under Saves.** Every slot shows a
**preview thumbnail** of the moment it was taken plus a timestamp, so you can
see which one is the fight you wanted rather than guessing from a date. The
selected slot is what **Y** loads, and the choice is remembered between
sessions. That tab also has per-slot Save/Load buttons and a three-deep
autosave ring below the manual slots.

Save states are separate from the game's own save file: they capture exactly
where you are standing, mid-cutscene included. `tmc.sav` is still what the
in-game save menu writes.

**Loading a state from an earlier play session** brings back your inventory,
flags, health and position and re-enters that room fresh — enemies respawn and
any cutscene in progress restarts — and the toast says "room re-entered".
Within the same session loads are exact. States saved by versions before 1.3.0
show as empty slots.

X is unused and stays free for the port's optional extra item slots.

If MENU does not open the settings overlay (muOS may claim the button before
the port sees it), use the on-screen **"L"** prompt on the file-select screen,
or F8 on a USB keyboard. Everything under *Known limitations* can be changed
there.

The port's optional **roll-attack macro** is bound to `d`, which no button on
this device emits — the SP has no spare button, and no L3/R3. Roll normally
instead. To use it, edit `tmc_pc.gptk` and give `d` to a button you can spare.

## Picture / scaling

Open the settings overlay and cycle **Display → Aspect mode**:

| Mode | What you get |
|---|---|
| **Stretch to fill** (default) | Fills the 640x480 panel. ~12% vertical stretch (the GBA is 3:2, the panel 4:3). |
| **Pixel perfect (integer)** | Exact 2x — every game pixel becomes an identical 2x2 block. Sharpest and most even, but a 480x320 image with black bars all round. |
| **Native 3:2 (GBA)** | Correct geometry, bars top and bottom. Still a fractional 2.667x, so pixel widths are slightly uneven. |
| Widescreen / Ultrawide | For wide monitors; not useful here. |

On other panels the launcher seeds this once from the screen size: 1:1 and
16:9 screens get *Pixel perfect*, and *Internal scale* is chosen so whole
copies of the prescaled frame fill the panel (3 on a 720x720 CubeXX/RGB30,
2 on a 1280x720 TrimUI Smart Pro). *Fullscreen* cannot be turned off under
the kiosk compositor, and the **Widescreen** toggle does nothing in this
build: the Linux binary renders the native 240-pixel width. Both are
expected.

The port runs on a 640x480 X screen matching the panel exactly, so the
compositor does no scaling and adds no blur. Only *Pixel perfect* has truly
uniform pixels — the others scale by 2.667x, which lands source pixels in
runs of 2 and 3.

## Known limitations on the RG35XX SP

This is a software-rendered GBA engine running on four Cortex-A53 cores, under
a compositor, with no working KMS. It is playable, not perfect:

- **Full game speed, 40-60 FPS.** The game always ticks at 60; what varies is
  how many of those frames reach the panel, because copying each frame to the
  compositor blocks the game for 5-17 ms on this device. Busy scenes and a
  screen that has been still for a moment show more doubled frames. If you
  change *Display → Internal scale* away from 2 it gets much worse — that
  setting is what makes 60 reachable at all here, counter-intuitive as it
  looks.
- **Fast-forward (R2) runs at 5-9x with the screen at ~30 Hz.** Presenting
  is what costs speed here: every displayed frame is a raster plus a copy
  through Xwayland and the compositor, and past ~30 presents a second those
  starve the game thread (60 Hz presenting leaves only ~2.5x). Below that
  the picture turns into a slideshow, so `fast_forward_fps` sits at 35,
  which lands at ~30 real presents a second on this device.
- **Upstream is work-in-progress.** Rendering and gameplay bugs that are not
  specific to this device belong at
  [999sian/tmc/issues](https://github.com/999sian/tmc/issues).

## Saves and settings

Everything the port writes stays inside `ports/picori/`:

| File / folder      | What it is                                    |
|--------------------|-----------------------------------------------|
| `tmc.sav`          | In-game save (EEPROM)                         |
| `state_*.bin`      | Save states (`state_auto_*` are the autosave ring) |
| `state_*.thumb`    | Preview thumbnails for the slot picker        |
| `config.json`      | Your settings                                 |
| `assets/`, `assets_src/`, `rom_data/` | Generated from your ROM on first launch |

Back up `tmc.sav` and `state_*.bin` before reinstalling — reinstalling
also overwrites `config.json` with the shipped defaults. The generated asset
folders can be deleted safely; they are rebuilt on the next launch (another
~2 minute wait).

A log of the last run is written to `ports/picori/log.txt`, and the run before
it to `log.prev.txt`. Include `log.txt` in any bug report.

## Reporting problems

This port is complete but **not actively maintained** — file reports in the
tracker rather than messaging the porter, so that whoever picks the project up
next can find them:

| Kind of problem | Where |
|---|---|
| Launcher, install, controls, audio routing, this device | [muos-rg35xx-sp-picori/issues](https://github.com/lorencouse/muos-rg35xx-sp-picori/issues) |
| Rendering or gameplay bugs not specific to a handheld | [999sian/tmc/issues](https://github.com/999sian/tmc/issues) |

Anyone is welcome to take the port over; it is GPL-3.0-or-later and needs no
permission. See *Taking this over* in the packaging repository.

## Credits

- **Project Picori** — [999sian](https://github.com/999sian/tmc) and contributors (GPL-3.0-or-later)
- **Decompilation** — [zeldaret/tmc](https://github.com/zeldaret/tmc)
- **Port / packaging** — lorencouse

## Licence and source

`tmc_pc` is licensed **GPL-3.0-or-later**. The full licence text is in
`LICENSE` beside this file.

The exact source this binary was built from is the tag
[`v0.8.3-sp4`](https://github.com/lorencouse/tmc/releases/tag/v0.8.3-sp4) of
[lorencouse/tmc](https://github.com/lorencouse/tmc) (a fork of
[999sian/tmc](https://github.com/999sian/tmc) adding handheld-specific audio,
UI-scale and aspect changes). The launcher and packaging are in
[muos-rg35xx-sp-picori](https://github.com/lorencouse/muos-rg35xx-sp-picori)
under the same licence.

*The Legend of Zelda* and The Minish Cap are property of Nintendo. This port
grants no rights to Nintendo's intellectual property and ships no game data.
