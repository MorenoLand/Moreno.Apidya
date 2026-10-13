class_name Copper
extends RefCounted
## Runs an Amiga Copper list (MOVE/WAIT only) and returns the 32-entry palette in effect on every video
## line. Used to reproduce the per-scanline colour gradients (sky, water) of the original.

const LINES := 320

## `data` = unpacked file, `base` = its RAM load address, `addr` = RAM address of the Copper list,
## `base_palette` = the 32 RGB444 words the CPU writes at level start.
static func line_palettes(data: PackedByteArray, base: int, addr: int, base_palette: PackedInt32Array) -> Array:
	var colors := base_palette.duplicate()
	var events: Array = []          # [line, color_index, value]
	var line := 0
	var last_v := -1
	var wrap := 0
	var o := addr - base
	for _n in 4000:
		if o + 4 > data.size():
			break
		var a := BE.u16(data, o)
		var b := BE.u16(data, o + 2)
		o += 4
		if a == 0xFFFF and b == 0xFFFE:
			break
		if a & 1:
			var v := (a >> 8) & 0xFF
			if v < last_v:
				wrap += 256
			last_v = v
			line = v + wrap
		elif a >= 0x180 and a <= 0x1BE:
			events.append([line, (a - 0x180) >> 1, b & 0xFFF])
	var rows: Array = []
	var ei := 0
	for l in LINES:
		while ei < events.size() and events[ei][0] <= l:
			colors[events[ei][1]] = events[ei][2]
			ei += 1
		rows.append(colors.duplicate())
	return rows


static func rows_to_image(rows: Array) -> Image:
	var buf := PackedByteArray()
	buf.resize(32 * LINES * 4)
	var p := 0
	for l in LINES:
		var r: PackedInt32Array = rows[l]
		for c in 32:
			var v: int = r[c]
			buf[p] = ((v >> 8) & 15) * 17
			buf[p + 1] = ((v >> 4) & 15) * 17
			buf[p + 2] = (v & 15) * 17
			buf[p + 3] = 255
			p += 4
	return Image.create_from_data(32, LINES, false, Image.FORMAT_RGBA8, buf)
