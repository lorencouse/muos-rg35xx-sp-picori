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
| X, Y     | soft slots  | Extra item slots, assigned in the pause menu |
| L2, R2   | soft slots  | As above                                 |
| D-pad    | D-pad       |                                          |
| START    | Start       | Pause menu                               |
| SELECT   | Select      |                                          |
| MENU     | F8          | Port settings overlay                    |

If MENU does not open the settings overlay (muOS may claim the button before
the port sees it), use the on-screen **"L"** prompt on the file-select screen,
or F8 on a USB keyboard. Everything under *Known limitations* can be changed
there.

The port's optional **roll-attack macro** is bound to `d`, which no button on
this device emits — the SP has no spare button, and no L3/R3. Roll normally
instead. To use it, edit `tmc_pc.gptk` and give `d` to a button you can spare.

## Known limitations on the RG35XX SP

This is a software-rendered GBA engine running on four Cortex-A53 cores, under
a compositor, with no working KMS. It is playable, not perfect:

- **~30 FPS render, full 60 TPS game speed.** The game logic runs at correct
  speed; the picture updates at half that. Raising the cap makes it worse, not
  better — the port's overload guard trips and it drops to ~12 FPS.
- **The picture is stretched ~12%.** The game is natively 3:2 and the panel is
  4:3, so `aspect_mode` ships as `"stretch"` to fill the screen. Set it to
  `"none"` under *Display → Aspect mode* if you would rather have black bars
  top and bottom with correct geometry.
- **Upstream is work-in-progress.** Rendering and gameplay bugs that are not
  specific to this device belong at
  [999sian/tmc/issues](https://github.com/999sian/tmc/issues).

## Saves and settings

Everything the port writes stays inside `ports/picori/`:

| File / folder      | What it is                                    |
|--------------------|-----------------------------------------------|
| `tmc.sav`          | In-game save (EEPROM)                         |
| `state_auto_*.bin` | Rolling autosave states                       |
| `config.json`      | Your settings                                 |
| `assets/`, `assets_src/`, `rom_data/` | Generated from your ROM on first launch |

Back up `tmc.sav` and `state_auto_*.bin` before reinstalling — reinstalling
also overwrites `config.json` with the shipped defaults. The generated asset
folders can be deleted safely; they are rebuilt on the next launch (another
~2 minute wait).

A log of the last run is written to `ports/picori/log.txt`, and the run before
it to `log.prev.txt`. Include `log.txt` in any bug report.

## Credits

- **Project Picori** — [999sian](https://github.com/999sian/tmc) and contributors (GPL-3.0-or-later)
- **Decompilation** — [zeldaret/tmc](https://github.com/zeldaret/tmc)
- **Port / packaging** — lorencouse
- Handheld build: [lorencouse/tmc @ rg35xx-sp-audio-ui](https://github.com/lorencouse/tmc/tree/rg35xx-sp-audio-ui)

*The Legend of Zelda* and The Minish Cap are property of Nintendo. This port
grants no rights to Nintendo's intellectual property and ships no game data.
