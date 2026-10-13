class_name Hud
extends RefCounted
## The two HUD strips of the original, drawn from its own panel bitmaps (file 1 of the disk, which the
## game keeps in chip RAM at $4B200): a top strip with the 1UP / 2UP plates, the BCD score digits and the
## spare ships of both players, and a bottom strip with the eight power-up plates.
##
## Both strips are two bitplane hi-res bitmaps (colour 0 is see-through). The active player's plate and the
## highlighted power-up plate show a sprite pair that sits behind the bitmap: it is only visible where the
## bitmap is colour 0. The result is a 640 x 259 picture (hi-res columns, video lines 40..298) that is laid
## over the 320 pixel wide playfield.

const W := 640
const H := 259

const FILE_BASE := 0x4B200
const TOP_P0 := 0x4F9A0 - FILE_BASE
const TOP_P1 := 0x4FC20 - FILE_BASE
const TOP_STRIDE := 80
const TOP_ROWS := 8
const TOP_X := 84               # hi-res column of the bitmap's first pixel
const BOT_P0 := 0x4F400 - FILE_BASE
const BOT_P1 := 0x4F6D0 - FILE_BASE
const BOT_STRIDE := 72
const BOT_ROWS := 9             # the tenth row is below the display window
const BOT_X := 54
const BOT_ROW := 250            # picture row of the bottom strip (video line 290)

const SCORE_BYTE := [7, 41]     # first digit column of each player's score
const LIVES_BYTE := [19, 38]    # first spare ship cell; player 2's cells run towards lower columns
const LIVES_MAX := 5
const BAR_X := [43, 253]        # sprite x (lowres) of the active player marker, 23 pixels, rows 38..46
const BAR_W := 23
const SLOT_X := [39, 69, 101, 131, 163, 193, 225, 256]    # lowres x of the highlight of each power-up slot
const SLOT_W := 21

# the top strip's palette (colour 3) and the metal sheen of colour 2 line by line
const COL1 := 0x666
const COL3_TOP := 0xFC0
const COL2_BOT := [0x999, 0xAAA, 0xBBB, 0xCCC, 0xBBB, 0xAAA, 0x999, 0x888, 0x888]
const COL2_TOP := [0x999, 0xAAA, 0xBBB, 0xCCC, 0xBBB, 0xAAA, 0x999, 0x888]
const BAR_COLOR := 0xFFF
const PULSE := [0x800, 0x900, 0xA00, 0xB00, 0xC00, 0xD00, 0xE00, 0xF00, 0xF00, 0xE00, 0xD00, 0xC00, 0xB00,
		0xA00, 0x900, 0x800]
const PULSE_TICKS := 2

# one spare ship: 2 bytes x 7 rows in each plane
const SHIP0 := [0x02, 0x00, 0x00, 0x20, 0xD6, 0x7E, 0xD7, 0xFE, 0xFE, 0x7E, 0x00, 0x20, 0x02, 0x00]
const SHIP1 := [0x01, 0xE0, 0x03, 0xC0, 0x55, 0xCC, 0xD6, 0xFE, 0x55, 0xCC, 0x03, 0xC0, 0x01, 0xE0]

# the first two score glyphs ("0" and "1") of the level code's digit table: how to find it in a level file
const DIGIT_SIGNATURE := [0x7E, 0xE7, 0xE7, 0xE7, 0xE7, 0xE7, 0x7E, 0x00, 0x3C, 0x1C, 0x1C, 0x1C, 0x1C, 0x1C,
		0x1C, 0x00]

var texture: ImageTexture
var ok := false

var _top0 := PackedByteArray()
var _top1 := PackedByteArray()
var _bot0 := PackedByteArray()
var _bot1 := PackedByteArray()
var _digits := PackedByteArray()
var _rgba := PackedByteArray()
var _image: Image

var _score := -1
var _lives := -1
var _slot := 0
var _player := 0                 # 0 = 1UP, 1 = 2UP is the active one
var _pulse_t := 0
var _dirty := true
var _slot_dirty := true
var _slot_changed := false
var _old_slot := 0


## `panel` is file 1 of the disk, `level_file` the level's code and data file (it holds the digit glyphs).
func setup(panel: PackedByteArray, level_file: PackedByteArray) -> void:
	if panel.size() < BOT_P1 + BOT_STRIDE * 10:
		return
	_top0 = panel.slice(TOP_P0, TOP_P0 + TOP_STRIDE * TOP_ROWS)
	_top1 = panel.slice(TOP_P1, TOP_P1 + TOP_STRIDE * TOP_ROWS)
	_bot0 = panel.slice(BOT_P0, BOT_P0 + BOT_STRIDE * BOT_ROWS)
	_bot1 = panel.slice(BOT_P1, BOT_P1 + BOT_STRIDE * BOT_ROWS)
	_digits = _find_digits(level_file)
	_rgba.resize(W * H * 4)
	_image = Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, _rgba)
	texture = ImageTexture.create_from_image(_image)
	ok = true
	_draw_bottom()
	set_score(0)
	set_lives(0)
	_dirty = false
	_draw_top()
	_update_texture()


func _find_digits(level_file: PackedByteArray) -> PackedByteArray:
	var n := DIGIT_SIGNATURE.size()
	for i in range(0, level_file.size() - 80):
		var hit := true
		for k in n:
			if level_file[i + k] != DIGIT_SIGNATURE[k]:
				hit = false
				break
		if hit:
			return level_file.slice(i, i + 80)
	return PackedByteArray()


func set_score(score: int) -> void:
	if not ok or score == _score:
		return
	_score = score
	var s := score % 1000000
	if _digits.size() >= 80:
		for k in 6:
			var digit := (s / int(pow(10, 5 - k))) % 10
			var col: int = SCORE_BYTE[_player] + k * 2
			for r in 7:
				var b := _digits[digit * 8 + r]
				_top0[(r + 1) * TOP_STRIDE + col] = b
				_top1[(r + 1) * TOP_STRIDE + col] = b
	_dirty = true


## `spare` = ships in reserve (the count of the original's $7C54), at most five are drawn. Without a
## second player the original shows the same count in both groups.
func set_lives(spare: int) -> void:
	if not ok or spare == _lives:
		return
	_lives = spare
	var shown := clampi(spare, 0, LIVES_MAX)
	for player in 2:
		for k in LIVES_MAX:
			var col: int = LIVES_BYTE[player] + (k * 2 if player == 0 else -k * 2)
			for r in 7:
				var a := TOP_STRIDE * r + col
				if k < shown:
					_top0[a] = SHIP0[r * 2]
					_top0[a + 1] = SHIP0[r * 2 + 1]
					_top1[a] = SHIP1[r * 2]
					_top1[a + 1] = SHIP1[r * 2 + 1]
				else:
					_top0[a] = 0
					_top0[a + 1] = 0
					_top1[a] = 0
					_top1[a + 1] = 0
	_dirty = true


## The highlighted power-up plate, 0 = none (the original's $7C20).
func set_slot(slot: int) -> void:
	if slot != _slot:
		_old_slot = _slot
		_slot = slot
		_slot_dirty = true
		_slot_changed = true


func tick(t: int) -> void:
	if not ok:
		return
	if _slot > 0 and (t % PULSE_TICKS) == 0:
		_pulse_t = (_pulse_t + 1) % PULSE.size()
		_slot_dirty = true
	var changed := false
	if _dirty:
		_dirty = false
		_draw_top()
		changed = true
	if _slot_dirty:
		_slot_dirty = false
		if _slot_changed:
			_slot_changed = false
			var old := _slot_span(_old_slot)
			if old.y > old.x:
				_draw_bottom(old.x, old.y)
		var span := _slot_span(_slot)
		if span.y > span.x:
			_draw_bottom(span.x, span.y)
		changed = true
	if changed:
		_update_texture()


func _update_texture() -> void:
	_image.set_data(W, H, false, Image.FORMAT_RGBA8, _rgba)
	texture.update(_image)


func _put(x: int, y: int, rgb12: int, a: int = 255) -> void:
	if x < 0 or x >= W:
		return
	var o := (y * W + x) * 4
	_rgba[o] = ((rgb12 >> 8) & 15) * 17
	_rgba[o + 1] = ((rgb12 >> 4) & 15) * 17
	_rgba[o + 2] = (rgb12 & 15) * 17
	_rgba[o + 3] = a


func _draw_top() -> void:
	var bar_x0: int = BAR_X[_player] * 2
	var bar_x1: int = bar_x0 + BAR_W * 2
	for y in TOP_ROWS:
		var row := y * TOP_STRIDE
		for x in W:
			var px := x - TOP_X
			var idx := 0
			if px >= 0 and px < TOP_STRIDE * 8:
				var sh := 7 - (px & 7)
				var o := row + (px >> 3)
				idx = ((_top0[o] >> sh) & 1) | (((_top1[o] >> sh) & 1) << 1)
			var c := 0
			match idx:
				1:
					c = COL1
				2:
					c = COL2_TOP[y]
				3:
					c = COL3_TOP
				_:
					# the active player's marker sprite shows through (video lines 38..46)
					c = BAR_COLOR if (y <= 6 and x >= bar_x0 and x < bar_x1) else 0
			_put(x, y, c)


func _slot_span(slot: int) -> Vector2i:
	if slot < 1 or slot > 8:
		return Vector2i(0, 0)
	var x0: int = int(SLOT_X[slot - 1]) * 2
	return Vector2i(x0, x0 + SLOT_W * 2)


## Draws the bottom strip between two hi-res columns; the highlight sprite shows through colour 0.
func _draw_bottom(from_x: int = 0, to_x: int = W) -> void:
	var span := _slot_span(_slot)
	var glow: int = PULSE[_pulse_t]
	for y in BOT_ROWS:
		var row := y * BOT_STRIDE
		for x in range(maxi(from_x, 0), mini(to_x, W)):
			var px := x - BOT_X
			var idx := 0
			if px >= 0 and px < BOT_STRIDE * 8:
				var sh := 7 - (px & 7)
				var o := row + (px >> 3)
				idx = ((_bot0[o] >> sh) & 1) | (((_bot1[o] >> sh) & 1) << 1)
			var c := 0
			match idx:
				1:
					c = COL1
				2:
					c = COL2_BOT[y]
				3:
					c = COL3_TOP
				_:
					c = glow if (x >= span.x and x < span.y) else 0
			_put(x, BOT_ROW + y, c)
