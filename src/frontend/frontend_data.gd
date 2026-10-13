class_name FrontEndData
extends RefCounted
## Everything the original front end (disk file 0: title, story, options, high scores) is made of,
## read from the unpacked file at runtime. All addresses are Amiga RAM addresses (file base $0A00).

const BASE := 0xA00
const FONT := 0xFE90                # 44 glyph columns x 8 rows, 1 bit per pixel, row stride 44 bytes
const FONT_STRIDE := 44

# 17-word palette blocks (16 colours + the colour of the story text strip)
const PAL_TITLE := 0x4FE4
const PAL_CASTLE := 0x506C
const PAL_SORCERER := 0x5006
const PAL_CABIN := 0x50F4
const PAL_WOMAN := 0x517C
const PAL_HERO := 0x515A
const PAL_OPTIONS := 0x51E2         # 4 colours: black, light green, light blue, white

# RLE-packed pictures: [source address, unpacked length]
const PIC_TITLE := [0x10000, 40960]      # 320x256, 4 planes (stride $2800)
const PIC_CASTLE := [0x1738A, 12288]     # 192x128, 4 planes (stride $C00)
const PIC_SORCERER := [0x13F26, 19472]   # first 12288 bytes are the picture
const PIC_CABIN := [0x1D936, 12288]
const PIC_WOMAN := [0x2D2F6, 12288]
const PIC_HERO := [0x24801, 73728]       # six 12288-byte frames

const STORY_PTRS := 0x5532               # page text pointers (.l)
const STORY_TIMES := 0x555A              # page durations in frames (.w)
const STORY_PAGES := 10
const DIFFICULTY_NAMES := 0x4680         # 4 x 8 characters
const OPTION_TEXT := 0x5849              # plane 0: labels and default values
const OPTION_VALUES := 0x592A            # plane 1: every selectable value
const OPTION_TABLES := [0x3F0A, 0x3F3E, 0x3F5C, 0x3FA8, 0x3FF4, 0x4034]  # level, lives, team, xtra, 1up, control
const OPTION_COUNTS := [4, 3, 3, 3, 4, 2]
const SOUND_TEST := 0x405C               # 25 x 16 bytes: 14 char name, module, song
const SOUND_TEST_COUNT := 25
const DEFAULT_SCORES := 0x5A3E           # 5 x 16 bytes (score BCD.l, name 10, difficulty.w) + 7 option words

var d := PackedByteArray()


func _init(disks: DiskSet) -> void:
	d = disks.get_data(0)


func u8(a: int) -> int:
	return d[a - BASE]


func u16(a: int) -> int:
	return BE.u16(d, a - BASE)


func u32(a: int) -> int:
	return BE.u32(d, a - BASE)


func cstr(a: int) -> String:
	var o := a - BASE
	var e := o
	while e < d.size() and d[e] != 0:
		e += 1
	return d.slice(o, e).get_string_from_ascii()


## The front end's own RLE: byte with bit 7 set = literal run of (n & 0x7F) + 1 bytes, otherwise the next
## byte repeats n + 1 times.
func rle(src: int, length: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(length)
	var o := 0
	var p := src - BASE
	while o < length and p < d.size():
		var c: int = d[p]
		p += 1
		if c & 0x80:
			var n := (c & 0x7F) + 1
			for i in n:
				if o < length:
					out[o] = d[p + i]
					o += 1
			p += n
		else:
			var v: int = d[p]
			p += 1
			for i in c + 1:
				if o < length:
					out[o] = v
					o += 1
	return out


func picture(def: Array) -> PackedByteArray:
	return rle(def[0], def[1])


## RGB444 words of a palette block.
func palette(addr: int, count: int = 17) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(count)
	for i in count:
		out[i] = u16(addr + i * 2) & 0xFFF
	return out


## Planar bitmap -> one colour index per pixel. Writes into `out` (a w*8-wide buffer, or a larger screen
## buffer when `out_stride` / `out_x` / `out_y` are given); returns it.
static func planar_to_indexed(data: PackedByteArray, offset: int, width_bytes: int, height: int,
		planes: int, plane_stride: int, out: PackedByteArray = PackedByteArray(), out_stride: int = 0,
		out_x: int = 0, out_y: int = 0) -> PackedByteArray:
	var w := width_bytes * 8
	if out.is_empty():
		out.resize(w * height)
		out_stride = w
	for y in height:
		var dst := (out_y + y) * out_stride + out_x
		var row := offset + y * width_bytes
		for xb in width_bytes:
			var b0 := 0
			var b1 := 0
			var b2 := 0
			var b3 := 0
			var i := row + xb
			if i < data.size():
				b0 = data[i]
			if planes > 1 and i + plane_stride < data.size():
				b1 = data[i + plane_stride]
			if planes > 2 and i + 2 * plane_stride < data.size():
				b2 = data[i + 2 * plane_stride]
			if planes > 3 and i + 3 * plane_stride < data.size():
				b3 = data[i + 3 * plane_stride]
			var o := dst + xb * 8
			for k in 8:
				var s := 7 - k
				out[o + k] = ((b0 >> s) & 1) | (((b1 >> s) & 1) << 1) | (((b2 >> s) & 1) << 2) | (((b3 >> s) & 1) << 3)
	return out


## Column of the font strip for a character; -1 = blank. Mirrors the original's character routine.
static func glyph_column(ch: int) -> int:
	if ch >= 0x30 and ch <= 0x39:
		return 26 + ch - 0x30
	if ch > 0x39:
		if ch >= 0x41:
			return (ch & 0xDF) - 0x41
		if ch == 0x3E:
			return 42
		return 39
	match ch:
		0x21: return 38
		0x2C: return 37
		0x2D: return 40
		0x2E: return 36
	return -1


## Draws text into a 1-bit plane (40 bytes per row). Carriage return starts the next text row (8 lines).
func draw_text(plane: PackedByteArray, x_char: int, y_px: int, text: String) -> void:
	var row := 0
	var col := 0
	for i in text.length():
		var ch := text.unicode_at(i)
		if ch == 13:
			row += 1
			col = 0
			continue
		draw_char(plane, x_char + col, y_px + row * 8, ch)
		col += 1


func draw_char(plane: PackedByteArray, x_char: int, y_px: int, ch: int) -> void:
	var g := glyph_column(ch)
	for r in 8:
		var y := y_px + r
		if x_char < 0 or x_char >= 40 or y < 0 or y >= plane.size() / 40:
			continue
		plane[y * 40 + x_char] = 0 if g < 0 else d[FONT - BASE + FONT_STRIDE * r + g]


## Selectable value strings (padded so that each one lands in its own column).
func option_strings(opt: int) -> Array[String]:
	var out: Array[String] = []
	var tab: int = OPTION_TABLES[opt]
	for i in OPTION_COUNTS[opt]:
		out.append(cstr(u32(tab + i * 4)))
	return out


func sound_test_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in SOUND_TEST_COUNT:
		var a := SOUND_TEST + i * 16
		out.append({"name": d.slice(a - BASE, a - BASE + 14).get_string_from_ascii(),
				"module": u8(a + 14), "song": u8(a + 15)})
	return out


func story_pages() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in STORY_PAGES:
		out.append({"text": cstr(u32(STORY_PTRS + i * 4)), "frames": u16(STORY_TIMES + i * 2)})
	return out


func difficulty_name(i: int) -> String:
	var a := DIFFICULTY_NAMES + i * 8
	return d.slice(a - BASE, a - BASE + 8).get_string_from_ascii()


## Factory high score table and option defaults stored in the file.
func default_scores() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in 5:
		var a := DEFAULT_SCORES + i * 16
		var bcd := u32(a)
		out.append({"score": bcd_to_int(bcd), "name": d.slice(a + 4 - BASE, a + 14 - BASE).get_string_from_ascii().strip_edges(),
				"difficulty": u16(a + 14)})
	return out


func default_options() -> Array[int]:
	var out: Array[int] = []
	for i in 7:
		out.append(u16(DEFAULT_SCORES + 80 + i * 2))
	return out


static func bcd_to_int(v: int) -> int:
	var r := 0
	var m := 1
	for i in 8:
		r += ((v >> (i * 4)) & 15) * m
		m *= 10
	return r
