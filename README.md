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
| Arrow keys | Move |
| Space / Ctrl | Fire |
| Esc | Back to the level menu |

## Status

Early but playable prototype.

| | |
|---|---|
| Levels 1-4 | backgrounds (tiles, maps, per-scanline Copper gradients), scrolling, player, enemy waves and movement |
| Enemies | path followers, scroll-locked objects, polar movers; shooting, hit points, score |
| Not yet | level 5, bosses/guardians (native handler enemies), power-ups and weapon upgrades, music and sound effects, HUD graphics, title/story screens |

## How it works

`src/amiga/` decodes the original files:

- `DiskSet` reads the two disk images and the 22-entry file table of the original loader.
- `Tpwm` unpacks the game's LZSS packer.
- `LevelData` turns a level file into tiles, map, palette, enemy/player frames and wave tables.
- `Copper` runs the Copper list to get the palette in effect on every scanline.

`src/game/` is the new engine: a fixed 50 Hz loop that scrolls the map half a pixel per tick, spawns
enemies from the wave table when their column scrolls in and moves them with the original path/polar
scripts. Everything is drawn from colour-index textures through a per-scanline palette shader.

## Layout

```
src/amiga/      readers for the original disk format and level data
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
redot --headless --path . --script res://tests/test_sim.gd  -- --disks=<folder> --level=1
```

## Legal

*Apidya* belongs to its rights holders. This project isn't affiliated with or endorsed by them, includes
none of the game's files, and is meant for people who own the game. The code in this repository is MIT
licensed.
