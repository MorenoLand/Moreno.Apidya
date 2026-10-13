class_name LevelDefs
extends RefCounted
## Where everything lives inside each level's (unpacked) code/data file. All addresses are Amiga RAM
## addresses; the unpacked file is loaded at RAM_BASE ($0A00). Found by reverse engineering, see the notes.

const RAM_BASE := 0xA00

## Value of the wave column counter when the main loop starts (the original's code first draws the
## screen's worth of columns): a wave with column c appears when c - this columns have scrolled in.
const COL_START := {1: 21, 2: 21, 3: 21, 4: 20, 5: 20}

const LEVELS := {
	1: {"name": "Garden", "file": 2, "tiles": 0xC752, "planes": 5, "map": 0x1BD38, "cols": 460, "pal": 0x900A,
		"bobs": 0x750E, "bob_count": 73, "player": 0x89D4, "player_gfx": 0x1F320,
		"waves": 0x7CB0, "copper": 0x8348, "angle": 0x8858,
		"shots": 0x8F40, "ball_script": 0x6B96, "music_cols": [0xAC, 0x130], "phase": 0x8820,
		"item_gfx": 0x21080, "item_mask": 0x25062},
	2: {"name": "Pond", "file": 11, "tiles": 0xC8CC, "planes": 5, "map": 0x1DD98, "cols": 460, "pal": 0xA2BA,
		"bobs": 0x749E, "bob_count": 74, "player": 0x9C14, "player_gfx": 0x21380,
		"waves": 0x7B6C, "copper": 0x94BC, "angle": 0x9A80,
		"shots": 0xA1E4, "ball_script": 0x6E4C, "phase": 0x9A48,
		"item_gfx": 0x230E0, "item_mask": 0x2944E},
	3: {"name": "Sewer", "file": 13, "tiles": 0x1AA2E, "planes": 5, "map": 0xD94E, "cols": 360, "pal": 0x9ED2,
		"bobs": 0x7A26, "bob_count": 56, "player": 0x98D6, "player_gfx": 0x1037E,
		"waves": 0x7FD8, "copper": 0xAE2E, "angle": 0x9758,
		"shots": 0x9E06, "ball_script": 0x7570, "phase": 0x9720,
		"item_gfx": 0x11A12, "item_mask": 0x192EA},
	4: {"name": "Machine", "file": 15, "tiles": 0x28D88, "planes": 4, "map": 0xD068, "cols": 460, "pal": 0x8FA4,
		"bobs": 0x75E6, "bob_count": 66, "player": 0x8970, "player_gfx": 0x10650,
		"waves": 0x7E80, "copper": 0x8400, "angle": 0x87F4,
		"shots": 0x8ED8, "ball_script": 0x6E08, "phase": 0x87BC,
		"item_gfx": 0x10B48, "item_mask": 0x162AE,
		# the guardian's hall: while the routine at `routine` is the main loop's scene routine it redraws the
		# screen from a second tile map (15 rows of `stride` bytes), moved by `ptr` (first visible column) and
		# the hardware scroll phase at `shift`
		"room": {"routine": 0x5560, "map": 0x31808, "tiles": 0x2F888, "stride": 0x3C, "rows": 15, "cols": 50,
			"ptr": 0x57CE, "shift": 0x7D7E}},
	5: {"name": "Castle", "file": 17, "scroll": 2.0, "end_col": 0x44A, "tiles": 0x1A178, "planes": 4, "map": 0, "cols": 0, "pal": 0x89B8,
		"gen_map": {"init": 0xA00, "main": 0xAB0, "step": 0xD40, "col_var": 0x7ACC, "end_col": 0x44A,
			"ptr_var": 0x7AB8, "tiles": 0x1A178, "tile_bytes": 128, "tile_size": 0x1001, "row_bytes": 184,
			"right": 0x28},
		"bobs": 0x75D6, "bob_count": 38, "player": 0x8384, "player_gfx": 0x21590,
		"waves": 0x7BD0, "copper": 0x7FA8, "angle": 0x8204,
		"shots": 0x88EC, "ball_script": 0x726A, "phase": 0x81CC,
		"item_gfx": 0x22D80, "item_mask": 0x268BC},
}

## TFMX music per level: disk file of the module, and the two addresses the level code passes to the
## player's init routine (module start, sample base). Each level starts song 0.
const MUSIC := {
	0: {"file": 0, "mdat": 0xE000, "smpl": 0x343F2},   # front end (title / options), embedded in file 0
	1: {"file": 6, "mdat": 0x32000, "smpl": 0x33FD4},
	2: {"file": 7, "mdat": 0x2E000, "smpl": 0x308B0},
	3: {"file": 8, "mdat": 0x2E000, "smpl": 0x2FE94},
	4: {"file": 9, "mdat": 0x35000, "smpl": 0x375F0},
	5: {"file": 10, "mdat": 0x38000, "smpl": 0x39348},
}
