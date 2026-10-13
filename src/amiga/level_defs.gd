class_name LevelDefs
extends RefCounted
## Where everything lives inside each level's (unpacked) code/data file. All addresses are Amiga RAM
## addresses; the unpacked file is loaded at RAM_BASE ($0A00). Found by reverse engineering, see the notes.

const RAM_BASE := 0xA00

const LEVELS := {
	1: {"name": "Garden", "file": 2, "tiles": 0xC752, "planes": 5, "map": 0x1BD38, "cols": 460, "pal": 0x900A,
		"bobs": 0x750E, "bob_count": 73, "player": 0x89D4, "player_gfx": 0x1F320,
		"waves": 0x7CB0, "copper": 0x8348, "angle": 0x8858},
	2: {"name": "Pond", "file": 11, "tiles": 0xC8CC, "planes": 5, "map": 0x1DD98, "cols": 460, "pal": 0xA2BA,
		"bobs": 0x749E, "bob_count": 74, "player": 0x9C14, "player_gfx": 0x21380,
		"waves": 0x7B6C, "copper": 0x94BC, "angle": 0x9A80},
	3: {"name": "Sewer", "file": 13, "tiles": 0x1AA2E, "planes": 5, "map": 0xD94E, "cols": 360, "pal": 0x9ED2,
		"bobs": 0x7A26, "bob_count": 56, "player": 0x98D6, "player_gfx": 0x1037E,
		"waves": 0x7FD8, "copper": 0xAE2E, "angle": 0x9758},
	4: {"name": "Machine", "file": 15, "tiles": 0x28D88, "planes": 4, "map": 0xD068, "cols": 460, "pal": 0x8FA4,
		"bobs": 0x75E6, "bob_count": 66, "player": 0x8970, "player_gfx": 0x10650,
		"waves": 0x7E80, "copper": 0x8400, "angle": 0x87F4},
	5: {"name": "Castle", "file": 17, "tiles": 0x1A178, "planes": 4, "map": 0, "cols": 0, "pal": 0x89B8,
		"bobs": 0x75D6, "bob_count": 38, "player": 0x8384, "player_gfx": 0x21590,
		"waves": 0x7BD0, "copper": 0x7FA8, "angle": 0x8204},
}

## Music modules on disk: file index per module (levels use modules in this order)
const MUSIC_FILES := [6, 7, 8, 9, 10]
