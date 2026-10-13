# Moreno.Apidya

A fan port of *Apidya* (Kaiko / Play Byte, Amiga, 1992) to Godot / Redot.

This is **not** a recompilation or an emulator. The game's own data (maps, graphics, enemy waves and
movement scripts) is read at runtime from your own copy of the original disks and played by a
new engine written in GDScript. Nothing from the game is included in this repository: you bring your
own copy.

## What you need

- [Redot](https://www.redotengine.org/) 26.2 or Godot 4.3+ (nothing else to install).
- Your own copy of Apidya's disk data: `Disk.1` and `Disk.2` as installed by the WHDLoad package
  (`ApidyaKaiko/data`). They are ~1 MB each.

## Setup

1. Open the project in Redot / Godot and press Play.
2. If the game files aren't found you'll be asked for the folder that contains `Disk.1` and `Disk.2`.
   The choice is remembered.

You can also skip the dialog:

- copy `Disk.1` and `Disk.2` into `assets/original/`, or
- set the `APIDYA_DISKS` environment variable, or
- start with `-- --disks=<folder>` on the command line.

No path is hard-coded anywhere.

## Controls

| | |
|---|---|
| Arrow keys | Move / change options |
| Space / Enter / Ctrl | Fire (hold = repeat; hold ~1 s and release = charge blast) / confirm |
| X / Shift | Use the highlighted power-up (not needed in "auto" mode) |
| P | Pause (the music fades out; fire or P goes on) |
| M / S | Music off / on, sound effects off / on |
| Esc | Back (game -> front end, front end -> title, title -> quit) |
| F2 | Switch between the original 4:3 picture and stretched widescreen (remembered) |
| F11 | Fullscreen |
| 1-5 (options screen) | Jump straight into that level (developer shortcut) |

## Status

Early but playable prototype.

| | |
|---|---|
| Front end | title, story pages, options (level, lives, team mode, extra select, 1up, control, sound test), high scores and name entry, with the original pictures, palettes, font, texts and menu music |
| Levels 1-5 | backgrounds (tiles, maps, per-scanline Copper gradients; level 5's is produced by running its own scroller routine once and kept in `user://cache`), scrolling, player, enemy waves and movement |
| Enemies | path followers, scroll-locked objects, polar movers, timed formations; shooting, hit points, score |
| Power-ups | capsules drop when a formation is wiped out; the 8-slot meter (speed, bomb, spread / missile / wave weapons with their levels, option pods, shield, slow down) with the original's auto-use rules; all weapon shot types and the charge blast |
| Audio | all music and sound effects, rendered by the game's own replay routine (see below) |
| Enemy handlers | the shooters, cannons, plants, throwers, mini guardians and level guardians of all levels are the original's own routines, run from the level file by the 68000 interpreter (see below) |
| Power-ups | bombs (lobbed bomb and the two terrain crawlers) in addition to the weapons above |
| Playable | all five levels run from the start through their guardians; clearing a level carries score, ships and power-ups on to the next, the difficulty decides where the game ends (practice: after level 4 back to the menu, easy: after level 4 with the short ending, normal / hard: level 5 and the ending) |
| HUD | the original's two strips drawn from its own panel bitmaps: 1UP / 2UP plates with the active player's marker, score digits, spare ships (extra ship every 20000 / 40000 / once at 8000 / 5000 as chosen), the eight power-up plates with the pulsing highlight; texts in the original's font |
| Continue | "CONTINUE YES / NO" with three credits after the last ship is lost, as in the original |
| Ending | the original's own ending program (file 20 of the disk) is run in the interpreter: its pictures, texts and music (its software mixer is performed natively) |
| Level 4 hall | the guardian's hall is drawn from the second tile map the level's own routine scrolls |
| Not yet | exact explosion graphics, story animations, two player team mode, the bonus game |

## How it works

`src/amiga/` decodes the original files:

- `DiskSet` reads the two disk images and the 22-entry file table of the original loader.
- `Tpwm` unpacks the game's LZSS packer.
- `LevelData` turns a level file into tiles, map, palette, enemy/player frames and wave tables.
- `Copper` runs the Copper list to get the palette in effect on every scanline.

`src/audio/` plays the music and effects the way the original did: the game's TFMX replay routine
(it lives on disk 1) is executed by a small 68000 interpreter (`M68K`), which feeds a model of the
Amiga's four-channel DMA audio (`Paula`). `AudioManager` runs that on a worker thread and streams the
result, so songs and effects come straight from the original data with no pre-rendered audio.

`src/frontend/` is the front end: `FrontEndData` reads the front-end file (RLE pictures, palette blocks, the 8x8
font strip, texts, option tables, default high scores) and `FrontEnd` runs the screens with the original's
colour-fade engine and option handlers. The option screen is two 1-bit text planes (green labels, blue
alternatives, white selection), exactly like the original.

`src/game/handler_vm.gd` runs the original's enemy handlers (the guardians and the other special enemies,
which are small 68000 routines of the level file) in the same interpreter. Everything around them is
native: the handler sees the enemy record, a handful of engine variables and the engine services it calls
(bullets, explosions, sounds, music), which `VmSymbols` locates in each level file and the game answers
itself. The draw records and blitter copies a handler produces are turned into sprites.

`src/game/` is the new engine: a fixed 50 Hz loop that scrolls the map half a pixel per tick, spawns
enemies from the wave table when their column scrolls in and moves them with the original path/polar
scripts. Everything is drawn from colour-index textures through a per-scanline palette shader.

## Layout

```
src/amiga/      readers for the original disk format and level data
src/audio/      68000 interpreter, Paula model, TFMX player, audio manager
src/frontend/   title, story, options, high scores (reads the front-end file of the original)
src/game/       the game itself (level scene, enemies)
shaders/        indexed-colour + per-scanline palette shader
scenes/         start scene
tests/          headless checks (see below)
assets/original/ put your Disk.1 / Disk.2 here (git-ignored)
```

## Tests

With the game files available:

```
redot --headless --path . --script res://tests/test_data.gd -- --disks=<folder>
redot --headless --path . --script res://tests/test_frontend.gd -- --disks=<folder>
redot --headless --path . --script res://tests/test_scene.gd -- --disks=<folder>   # title -> options -> game -> scores
redot --headless --path . --script res://tests/test_sim.gd  -- --disks=<folder> --level=1
redot --headless --path . --script res://tests/test_sim.gd  -- --disks=<folder> --level=5 --ticks=30000 --god --chase --max   # plays a level with a simple autopilot
redot --path . --script res://tests/amiga_view.gd -- --disks=<folder> --level=1 --frames=300 --out=view     # picture of the original's own code run in the interpreter (reference)
redot --headless --path . --script res://tests/test_audio.gd -- --disks=<folder> --level=1 --seconds=10
redot --headless --path . --script res://tests/test_audio_all.gd -- --disks=<folder>   # every song/effect
redot --path . --script res://tests/shot.gd -- --disks=<folder> --out=shot.png --level=1 --ticks=700   # screenshot (needs a GPU)
redot --path . --script res://tests/shot_frontend.gd -- --disks=<folder> --out=fe                       # front end screenshots
```

## Legal

*Apidya* belongs to its rights holders. This project isn't affiliated with or endorsed by them, includes
none of the game's files, and is meant for people who own the game. The code in this repository is MIT
licensed.
