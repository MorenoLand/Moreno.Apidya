class_name OsdText
extends Sprite2D
## Text in the original's own 8 x 8 font (the glyph strip of file 1, at $4FE9F in chip RAM): white with a
## dark shadow one pixel down and to the right, every line centred on the screen. `text` can be changed
## like a Label's.

const FILE_BASE := 0x4B200
const FONT_START := 0x4FE9F - FILE_BASE     # glyph 0 (blank); glyph n is the n-th byte of every 44 byte row
const STRIDE := 44
const SCREEN_W := 320
const SHADOW := Color(0.2, 0.2, 0.25, 1.0)

static var _strip := PackedByteArray()

var text := "":
	set(v):
		if v != text:
			text = v
			_rebuild()


## `panel` is file 1 of the disk.
static func set_font(panel: PackedByteArray) -> void:
	if panel.size() >= FONT_START + STRIDE * 8:
		_strip = panel.slice(FONT_START, FONT_START + STRIDE * 8)


static func _glyph_index(c: String) -> int:
	var o := c.unicode_at(0)
	if o >= 0x41 and o <= 0x5A:
		return o - 0x40
	if o >= 0x61 and o <= 0x7A:
		return o - 0x60
	if o >= 0x30 and o <= 0x39:
		return o - 0x30 + 27
	match c:
		".":
			return 37
		",":
			return 38
		"!", ":":
			return 39
		"?":
			return 40
		"-":
			return 41
		">":
			return 42
	return 0


func _rebuild() -> void:
	if _strip.is_empty() or text.is_empty():
		texture = null
		return
	var lines := text.split("\n")
	var cols := 1
	for l in lines:
		cols = maxi(cols, l.length())
	var w := cols * 8 + 2
	var h := lines.size() * 8 + 1
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for li in lines.size():
		var line: String = lines[li]
		var x0 := (w - line.length() * 8) / 2
		for ci in line.length():
			var g := _glyph_index(line[ci])
			if g == 0:
				continue
			for r in 8:
				var bits := _strip[r * STRIDE + g]
				for b in 8:
					if (bits >> (7 - b)) & 1:
						var x := x0 + ci * 8 + b
						var y := li * 8 + r
						if x + 1 < w and y + 1 < h:
							img.set_pixel(x + 1, y + 1, SHADOW)
		for ci in line.length():
			var g := _glyph_index(line[ci])
			if g == 0:
				continue
			for r in 8:
				var bits := _strip[r * STRIDE + g]
				for b in 8:
					if (bits >> (7 - b)) & 1:
						img.set_pixel(x0 + ci * 8 + b, li * 8 + r, Color.WHITE)
	texture = ImageTexture.create_from_image(img)
	centered = false
	position.x = float((SCREEN_W - w) / 2)
