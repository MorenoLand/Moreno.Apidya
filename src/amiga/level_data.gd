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
var item_img: Image                       # power-up capsule, 16 x 15 LA8
var shot_art := {}                        # player shot / pod / enemy bullet images, see _load_shot_art
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
	d.item_img = d._planar_masked(def["item_gfx"], def["item_mask"], 1, 15, d.planes)
	d._load_shot_art(def)
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


## Sprite stored the way the shot blitter reads it: per row one word for every plane (rows * planes
## consecutive words), mask duplicated per plane. `w_words` excludes the extra shift word of the blit.
func _interleaved_masked(gfx_ram: int, mask_ram: int, w_words: int, rows: int) -> Image:
	var buf := PackedByteArray()
	buf.resize(w_words * 16 * rows * 2)
	var go := _off(gfx_ram)
	var mo := _off(mask_ram)
	var p := 0
	for y in rows:
		for wd in w_words:
			var mi := mo + ((y * planes) * w_words + wd) * 2
			var mw := BE.u16(raw, mi) if mi >= 0 and mi + 1 < raw.size() else 0
			var pw: Array[int] = []
			for pl in planes:
				var o := go + ((y * planes + pl) * w_words + wd) * 2
				pw.append(BE.u16(raw, o) if o >= 0 and o + 1 < raw.size() else 0)
			for x in 16:
				var m := 0x8000 >> x
				var c := 0
				for pl in planes:
					if pw[pl] & m:
						c |= 1 << pl
				buf[p] = c
				buf[p + 1] = 255 if (mw & m) else 0
				p += 2
	return Image.create_from_data(w_words * 16, rows, false, Image.FORMAT_LA8, buf)


## blit size word (rows * planes) << 6 | (width words + 1)
func _shot_image(gfx: int, mask: int, d3: int) -> Image:
	var w := (d3 & 63) - 1
	var rows := (d3 >> 6) / planes
	return _interleaved_masked(gfx, mask, maxi(w, 1), maxi(rows, 1))


func _weapon_frames(base: int) -> Array:
	var frames: Array = []
	for j in 4:
		var f := {}
		for k in 2:
			var gfx := BE.u32(raw, _off(base) + 0x20 * k + 4 * j)
			var mask := BE.u32(raw, _off(base) + 0x10 + 0x20 * k + 4 * j)
			var d3 := BE.u16(raw, _off(base) + 0x40 + 2 * k + 4 * j)
			var yoff := BE.s16(raw, _off(base) + 0x50 + 2 * k + 4 * j)
			f["a" if k == 0 else "b"] = {"img": _shot_image(gfx, mask, d3), "yoff": yoff}
		frames.append(f)
	return frames


## Finds every `move.w #D3,D3 / lea gfx.l,A3 / lea mask.l,A2` in the shot handlers (they sit in the
## same order in every level) and builds the shot / pod / enemy bullet images.
func _load_shot_art(def: Dictionary) -> void:
	var consts: Array = []
	var end := mini(raw.size() - 16, 0x6000 - LevelDefs.RAM_BASE)
	var i := 0
	while i < end:
		if raw[i] == 0x36 and raw[i + 1] == 0x3C and raw[i + 4] == 0x47 and raw[i + 5] == 0xF9 				and raw[i + 10] == 0x45 and raw[i + 11] == 0xF9:
			consts.append({"d3": BE.u16(raw, i + 2), "gfx": BE.u32(raw, i + 6), "mask": BE.u32(raw, i + 12)})
			i += 16
		else:
			i += 2
	var extra := 2 if consts.size() >= 17 else 0
	var imgs: Array = []
	for c in consts:
		imgs.append(_shot_image(c["gfx"], c["mask"], c["d3"]))
	shot_art["basic"] = imgs[0]
	shot_art["wave_a"] = [imgs[1], imgs[2], imgs[3]]
	shot_art["pod"] = imgs[4]
	shot_art["wave_b"] = [imgs[5 + extra], imgs[6 + extra], imgs[7 + extra]]
	shot_art["enemy_big"] = imgs[consts.size() - 1]
	var t1: int = def["shots"]
	shot_art["w1"] = _weapon_frames(t1)
	var w2 := _weapon_frames(t1 + 0x60)
	shot_art["w2"] = w2
	# enemy bullet frames: 8 pointers just before the first table; mask / size from the handler
	var eb: Array = []
	var ebm := _find_enemy_bullet_consts()
	for j in 8:
		var g := BE.u32(raw, _off(t1) - 0x20 + 4 * j)
		eb.append(_shot_image(g, ebm["mask"], ebm["d3"]))
	shot_art["eb"] = eb
	# option pods: 4 entries (gfx.l, mask.l, y offset.w, rows.w) right after the enemy phase table
	var pods: Array = []
	var pt := _off(def["phase"]) + 8
	for j in 4:
		var r := pt + j * 12
		var rows := BE.u16(raw, r + 10)
		pods.append({"img": _planar_masked(BE.u32(raw, r), BE.u32(raw, r + 4), 1, rows, planes),
			"yoff": BE.s16(raw, r + 8)})
	shot_art["pods"] = pods


## `move.w #D3,D3 / movea.l (var).w,A3 / lea mask.l,A2` of the enemy bullet handlers
func _find_enemy_bullet_consts() -> Dictionary:
	var end := mini(raw.size() - 16, 0x6000 - LevelDefs.RAM_BASE)
	var i := 0
	while i < end:
		if raw[i] == 0x36 and raw[i + 1] == 0x3C and raw[i + 4] == 0x26 and raw[i + 5] == 0x78 				and raw[i + 8] == 0x45 and raw[i + 9] == 0xF9:
			return {"d3": BE.u16(raw, i + 2), "mask": BE.u32(raw, i + 10)}
		i += 2
	return {"d3": 0x782, "mask": 0}


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
			# 8-byte entry: a formation group (list of timed enemies, power-up when `required` are killed)
			waves.append({"col": col, "group": true, "list": BE.u16(raw, o + 4),
				"required": raw[o + 6], "hold": raw[o + 7]})
			a += 8
			continue
		var w := {"col": col, "group": false, "type": t & 0x1FF, "flags": t >> 9,
			"x": BE.u16(raw, o + 4), "y": BE.u16(raw, o + 6),
			"hp": (BE.u16(raw, o + 8) >> 8) & 0x7F, "frame": BE.u16(raw, o + 8) & 0xFF,
			"script": BE.u16(raw, o + 10), "p6": BE.u16(raw, o + 12), "p7": BE.u16(raw, o + 14),
			"score_bcd": BE.u16(raw, o + 16), "fire_timer": raw[o + 18], "fire_reload": raw[o + 19],
			"handler": BE.u16(raw, o + 20), "p11": BE.u16(raw, o + 22)}
		waves.append(w)
		a += 24


## Formation list of a group: 24-byte entries `delay, type, x, y, hp/frame, timers, script, p7, score,
## offsets, handler, p11` until a word with bit 15 set. Same enemy fields as a wave entry, other order.
func decode_formation(list_ptr: int) -> Array:
	var res: Array = []
	var o := _off(list_ptr)
	for _i in 200:
		if o < 0 or o + 24 > raw.size():
			break
		var delay := BE.u16(raw, o)
		if delay & 0x8000:
			break
		var t := BE.u16(raw, o + 2)
		res.append({"delay": delay, "group": false, "type": t & 0x1FF, "flags": t >> 9,
			"x": BE.u16(raw, o + 4), "y": BE.u16(raw, o + 6),
			"hp": (BE.u16(raw, o + 8) >> 8) & 0x7F, "frame": BE.u16(raw, o + 8) & 0xFF,
			"fire_timer": raw[o + 10], "fire_reload": raw[o + 11], "script": BE.u16(raw, o + 12),
			"p7": BE.u16(raw, o + 14), "score_bcd": BE.u16(raw, o + 16), "p6": BE.u16(raw, o + 18),
			"handler": BE.u16(raw, o + 20), "p11": BE.u16(raw, o + 22)})
		o += 24
	return res


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
