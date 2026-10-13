class_name LevelData
extends RefCounted
## Everything one level needs, decoded from the original game files at runtime.

const ROWS := 15

var level := 0
var name := ""
var planes := 5
var cols := 0
var palette := PackedColorArray()         # 32 colours (RGB444 expanded)
var palette_words := PackedInt32Array()   # 32 x RGB444
var line_palette: Image                   # 32 x 320 RGBA8, palette in effect on each video line
var map_words := PackedInt32Array()       # ROWS * cols: tile | flags << 10
var bg_image: Image                       # R8, (cols*16) x 240, colour indices
var bob_frames: Array = []                # {img:Image(LA8), w, h, hit_w, hit_h, xoff, yoff, overlay}
var player_frames: Array = []             # [variant][frame] -> {img, w, h, yoff}
var waves: Array = []                     # dictionaries, see _parse_waves
var angle_table := PackedInt32Array()     # 24 signed 16.16 values, index (byte_off/4 + 8)
var raw: PackedByteArray                  # unpacked level file (RAM base $0A00)


static func load_level(disks: DiskSet, level_no: int) -> LevelData:
	var d := LevelData.new()
	var def: Dictionary = LevelDefs.LEVELS[level_no]
	d.level = level_no
	d.name = def["name"]
	d.planes = def["planes"]
	d.raw = disks.get_data(def["file"])
	d._load_palette(def)
	d._load_map(def)
	d._load_bobs(def)
	d._load_player(def)
	d._parse_waves(def)
	d._load_angles(def)
	return d


func _off(ram_addr: int) -> int:
	return ram_addr - LevelDefs.RAM_BASE


func _load_palette(def: Dictionary) -> void:
	var o := _off(def["pal"])
	palette_words.resize(32)
	palette.resize(32)
	for i in 32:
		var v := BE.u16(raw, o + i * 2) & 0xFFF
		palette_words[i] = v
		palette[i] = Color8(((v >> 8) & 15) * 17, ((v >> 4) & 15) * 17, (v & 15) * 17)
	var rows := Copper.line_palettes(raw, LevelDefs.RAM_BASE, def["copper"], palette_words)
	line_palette = Copper.rows_to_image(rows)


## Tile (16x16, `planes` bitplanes, stored by row: plane0..plane(n-1) word per scanline) -> 256 colour indices
func _decode_tile(t: int, tile_base_off: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(256)
	var tb := tile_base_off + t * planes * 32
	if tb + planes * 32 > raw.size():
		return out
	var rb := planes * 2
	for r in 16:
		var words: Array[int] = []
		for p in planes:
			words.append(BE.u16(raw, tb + r * rb + p * 2))
		for x in 16:
			var c := 0
			var m := 0x8000 >> x
			for p in planes:
				if words[p] & m:
					c |= 1 << p
			out[r * 16 + x] = c
	return out


func _load_map(def: Dictionary) -> void:
	cols = def["cols"]
	if cols == 0:
		return
	var mo := _off(def["map"])
	var tile_off := _off(def["tiles"])
	map_words.resize(ROWS * cols)
	var cache := {}
	var width := cols * 16
	var buf := PackedByteArray()
	buf.resize(width * 240)
	for r in ROWS:
		for c in cols:
			var w := BE.u16(raw, mo + (r * cols + c) * 2)
			map_words[r * cols + c] = w
			var t := w & 0x3FF
			if not cache.has(t):
				cache[t] = _decode_tile(t, tile_off)
			var px: PackedByteArray = cache[t]
			var dst := r * 16 * width + c * 16
			for y in 16:
				for x in 16:
					buf[dst + y * width + x] = px[y * 16 + x]
	bg_image = Image.create_from_data(width, 240, false, Image.FORMAT_R8, buf)


## Planar image + 1-plane mask -> LA8 image (L = colour index, A = 255 where the mask is set)
func _planar_masked(gfx_ram: int, mask_ram: int, w_words: int, h: int, nplanes: int) -> Image:
	var buf := PackedByteArray()
	buf.resize(w_words * 16 * h * 2)
	var go := _off(gfx_ram)
	var mo := _off(mask_ram)
	var p := 0
	var plane_size := h * w_words * 2
	for y in h:
		for wd in w_words:
			var mi := mo + (y * w_words + wd) * 2
			var mw := BE.u16(raw, mi) if mi >= 0 and mi + 1 < raw.size() else 0
			var pw: Array[int] = []
			for pl in nplanes:
				var o := go + pl * plane_size + (y * w_words + wd) * 2
				pw.append(BE.u16(raw, o) if o >= 0 and o + 1 < raw.size() else 0)
			for x in 16:
				var m := 0x8000 >> x
				var c := 0
				for pl in nplanes:
					if pw[pl] & m:
						c |= 1 << pl
				buf[p] = c
				buf[p + 1] = 255 if (mw & m) else 0
				p += 2
	return Image.create_from_data(w_words * 16, h, false, Image.FORMAT_LA8, buf)


func _load_bobs(def: Dictionary) -> void:
	var o := _off(def["bobs"])
	var count: int = def["bob_count"]
	for i in count:
		var r := o + i * 18
		var gfx := BE.u32(raw, r)
		var mask := BE.u32(raw, r + 4)
		var wf := BE.u16(raw, r + 8)
		var w := wf & 0x3FFF
		var h := BE.u16(raw, r + 10)
		var frame := {"w": w * 16, "h": h, "xoff": BE.s16(raw, r + 12), "yoff": BE.s16(raw, r + 14),
			"overlay": (wf & 0x4000) != 0, "hit_w": raw[r + 16], "hit_h": raw[r + 17]}
		if w >= 1 and w <= 12 and h >= 1 and h <= 140:
			frame["img"] = _planar_masked(gfx, mask, w, h, planes)
		bob_frames.append(frame)


func _load_player(def: Dictionary) -> void:
	var o := _off(def["player"])
	var gbase: int = def["player_gfx"]
	for v in 4:
		var variant: Array = []
		for f in 4:
			var r := o + v * 0x20 + f * 8
			var g := BE.u16(raw, r)
			var m := BE.u16(raw, r + 2)
			var s := BE.u16(raw, r + 4)
			var y := BE.s16(raw, r + 6)
			var h := s >> 6
			var w := (s & 63) - 1
			if h >= 4 and h <= 64 and w >= 1 and w <= 6:
				variant.append({"img": _planar_masked(gbase + g, gbase + m, w, h, planes), "w": w * 16, "h": h, "yoff": y})
		player_frames.append(variant)


func _load_angles(def: Dictionary) -> void:
	var a := _off(def["angle"])
	angle_table.resize(24)
	for k in range(-8, 16):
		var o := a + k * 4
		var v := BE.u32(raw, o) if o >= 0 else 0
		if v >= 0x80000000:
			v -= 0x100000000
		angle_table[k + 8] = v


## byte_off is the byte offset from the table start (may be negative), as used by the original code
func angle_entry(byte_off: int) -> int:
	return angle_table[(byte_off >> 2) + 8]


func _parse_waves(def: Dictionary) -> void:
	var a := BE.u32(raw, _off(def["waves"]))
	var guard := 0
	while guard < 500:
		guard += 1
		var o := _off(a)
		if o + 8 > raw.size():
			break
		var col := BE.u16(raw, o)
		if col == 0xFFFF:
			break
		var t := BE.u16(raw, o + 2)
		if t & 0x8000:
			waves.append({"col": col, "decor": true, "w1": t, "w2": BE.u16(raw, o + 4), "w3": BE.u16(raw, o + 6)})
			a += 8
			continue
		var w := {"col": col, "decor": false, "type": t & 0x1FF, "flags": t >> 9,
			"x": BE.u16(raw, o + 4), "y": BE.u16(raw, o + 6),
			"hp": (BE.u16(raw, o + 8) >> 8) & 0x7F, "frame": BE.u16(raw, o + 8) & 0xFF,
			"script": BE.u16(raw, o + 10), "p6": BE.u16(raw, o + 12), "p7": BE.u16(raw, o + 14),
			"score_bcd": BE.u16(raw, o + 16), "fire_timer": raw[o + 18], "fire_reload": raw[o + 19],
			"handler": BE.u16(raw, o + 20), "p11": BE.u16(raw, o + 22)}
		waves.append(w)
		a += 24


## --- AI script decoding (used by the game at spawn time) ---------------------------------------------

## Path (types 2/3): steps {dur, dx, dy} or {frame}; executed from ptr+3 (see notes)
func decode_path(ptr: int) -> Array:
	var steps: Array = []
	var a := _off(ptr) + 3
	for _i in 600:
		if a < 0 or a + 2 >= raw.size():
			break
		var dur: int = raw[a]
		if dur == 0:
			steps.append({"frame": raw[a + 1]})
			a += 2
		elif dur & 0x80:
			break
		else:
			steps.append({"dur": dur, "dx": BE.s8(raw, a + 1), "dy": BE.s8(raw, a + 2)})
			a += 3
	return steps


## Script list: entries of 4 bytes starting at script+4: path.w, ?.b, repeat.b ; path 0xFFFF ends.
func decode_script(script_ptr: int) -> Array:
	var res: Array = []
	var a := _off(script_ptr) + 4
	for _i in 64:
		if a < 0 or a + 3 >= raw.size():
			break
		var p := BE.u16(raw, a)
		if p == 0xFFFF:
			break
		res.append({"steps": decode_path(p), "repeat": raw[a + 3]})
		a += 4
	return res


## Polar movers (types >= 6): pairs [code dur]
func decode_polar(script_ptr: int) -> Array:
	var res: Array = []
	var a := _off(script_ptr)
	for _i in 200:
		if a < 0 or a + 1 >= raw.size():
			break
		var c: int = raw[a]
		if c == 0xFF:
			break
		if c < 0x80:
			res.append({"code": c, "dur": raw[a + 1]})
		else:
			res.append({"frame": c & 0x7F, "dur": raw[a + 1]})
		a += 2
	return res
