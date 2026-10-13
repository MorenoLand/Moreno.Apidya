class_name FrontEnd
extends Control
## The original front end rebuilt natively: title, story pages, options, high scores and name entry.
## Pictures, palettes, font and every string come from the game's own front-end file (FrontEndData);
## the screen logic follows the original's option handlers and fade engine.

signal start_game(options: Dictionary)
signal quit_requested

const W := 320
const H := 256
const PIC_X := 64                  # 192 x 128 story pictures sit centred
const PIC_Y := 13
const STRIP_Y := 180               # one-bitplane story text strip (rows 180..243)
const STRIP_ROWS := 64
const TEXT_IDX := 16               # palette entry of the story text
const TEXT_COLOUR := 0xFDF
const GAP_FRAMES := 36
const OPT_X := 18                  # value column (characters)
const OPT_Y := 54                  # y of the first option line, 16 pixels per line
const SAVE_COL := 16
const START_COL := 2
const TABLE_Y := 30                # text screens start 6 lines below the third character row

enum Mode { ATTRACT, OPTIONS, SCORES, NAME, TRANSITION }

# picture, palette block, frames shown (the title is a full screen, the others 192 x 128)
const SCENES := [
	{"id": "title", "pal": FrontEndData.PAL_TITLE, "frames": 2000},
	{"id": "castle", "pal": FrontEndData.PAL_CASTLE, "frames": 800},
	{"id": "sorcerer", "pal": FrontEndData.PAL_SORCERER, "frames": 800},
	{"id": "cabin", "pal": FrontEndData.PAL_CABIN, "frames": 700},
	{"id": "woman", "pal": FrontEndData.PAL_WOMAN, "frames": 600},
	{"id": "hero", "pal": FrontEndData.PAL_HERO, "frames": 700},
]

const ONE_UP := [[20000, true], [40000, true], [8000, false], [5000, false]]


## Colour fade engine of the original: every second frame each differing colour moves by 1/16 of the
## distance (per RGB channel), so a complete fade takes 16 steps = 32 frames.
class Fader:
	var cur := PackedInt32Array()
	var target := PackedInt32Array()
	var _acc := PackedInt32Array()
	var _diff := PackedInt32Array()
	var _tick := 0

	func _init() -> void:
		cur.resize(32)
		target.resize(32)
		_acc.resize(96)
		_diff.resize(96)

	static func _nib(w: int, c: int) -> int:
		return (w >> (8 - 4 * c)) & 15

	func set_colour(i: int, w: int) -> void:
		cur[i] = w
		target[i] = w
		for c in 3:
			_acc[i * 3 + c] = _nib(w, c) * 16
			_diff[i * 3 + c] = 0

	func fade_colour(i: int, w: int) -> void:
		target[i] = w
		for c in 3:
			_acc[i * 3 + c] = _nib(cur[i], c) * 16
			_diff[i * 3 + c] = _nib(w, c) - _nib(cur[i], c)

	func fade_to(words: PackedInt32Array, first: int, count: int) -> void:
		for i in count:
			var w := 0
			if first + i < words.size():
				w = words[first + i]
			fade_colour(first + i, w)

	## One video frame; returns true when a colour changed.
	func step() -> bool:
		_tick += 1
		if _tick & 1:
			return false
		var changed := false
		for i in 32:
			if cur[i] == target[i]:
				continue
			var w := 0
			for c in 3:
				_acc[i * 3 + c] += _diff[i * 3 + c]
				w |= clampi(_acc[i * 3 + c] >> 4, 0, 15) << (8 - 4 * c)
			cur[i] = w
			changed = true
		return changed


var _disks: DiskSet
var _data: FrontEndData
var _audio: AudioManager
var _audio_level := -1
var _pending_result := {}

var _arc: AspectRatioContainer
var _rect: TextureRect
var _toast: Label
var _idx := PackedByteArray()
var _idx_img: Image
var _idx_tex: ImageTexture
var _pal_img: Image
var _pal_tex: ImageTexture
var _fader := Fader.new()
var _widescreen := false

var _mode := Mode.ATTRACT
var _tick_count := 0

# attract loop
var _scene := -1
var _scene_t := 0
var _gap_t := 0
var _fading_out := false
var _hero_screens: Array[PackedByteArray] = []
var _hero_frame := 0
var _pages: Array[Dictionary] = []
var _page := -1
var _page_t := 180
var _page_on := false
var _strip := PackedByteArray()

# transition
var _trans_t := 0
var _trans_cb := Callable()

# options
var _p0 := PackedByteArray()
var _p1 := PackedByteArray()
var _opts: Array[int] = []              # level, lives, teammode, xtra, 1up, control, bgm
var _opt_strings: Array = []
var _sel := 7
var _on_save := false
var _sounds: Array[Dictionary] = []
var _saved_flash := 0

# scores / name entry
var _scores: Array[Dictionary] = []
var _new_score := {}
var _entry_name := ""
var _entry_rank := -1
var _cursor_t := 0


## `result` = {"score", "difficulty"} to open on the high score table / name entry after a game.
func setup(disks: DiskSet, result: Dictionary = {}) -> void:
	_disks = disks
	_pending_result = result


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_data = FrontEndData.new(_disks)
	_pages = _data.story_pages()
	_sounds = _data.sound_test_entries()
	for i in FrontEndData.OPTION_TABLES.size():
		_opt_strings.append(_data.option_strings(i))
	_load_settings()

	var back := ColorRect.new()
	back.color = Color.BLACK
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	_arc = AspectRatioContainer.new()
	_arc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_arc.ratio = 4.0 / 3.0
	add_child(_arc)

	_idx.resize(W * H)
	_idx_img = Image.create_from_data(W, H, false, Image.FORMAT_R8, _idx)
	_idx_tex = ImageTexture.create_from_image(_idx_img)
	_pal_img = Image.create(32, 1, false, Image.FORMAT_RGB8)
	_pal_tex = ImageTexture.create_from_image(_pal_img)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/front_end.gdshader") as Shader
	mat.set_shader_parameter("palette", _pal_tex)
	_rect = TextureRect.new()
	_rect.texture = _idx_tex
	_rect.material = mat
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_arc.add_child(_rect)

	_toast = Label.new()
	_toast.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toast.visible = false
	add_child(_toast)

	resized.connect(_apply_aspect)
	_widescreen = bool(Settings.get_value("widescreen", false))
	_apply_aspect()

	_audio = AudioManager.new()
	add_child(_audio)
	_strip.resize(40 * STRIP_ROWS)
	if _pending_result.is_empty():
		_enter_attract(true)
	else:
		_show_result(_pending_result["score"], _pending_result["difficulty"])


func _exit_tree() -> void:
	if _audio != null:
		_audio.stop()


# ---- settings ---------------------------------------------------------------------------------------
func _load_settings() -> void:
	var defaults := _data.default_options()
	var saved: Variant = Settings.get_value("fe_options", [])
	_opts.clear()
	for i in 7:
		var v: int = defaults[i]
		if saved is Array and saved.size() == 7:
			v = int(saved[i])
		_opts.append(v)
	_clamp_options()
	_scores = _data.default_scores()
	var sv: Variant = Settings.get_value("fe_scores", [])
	if sv is Array and sv.size() == 5:
		var loaded: Array[Dictionary] = []
		for e in sv:
			if e is Dictionary and e.has("score") and e.has("name"):
				loaded.append({"score": int(e["score"]), "name": str(e["name"]),
						"difficulty": int(e.get("difficulty", 2))})
		if loaded.size() == 5:
			_scores = loaded


func _clamp_options() -> void:
	_opts[0] = clampi(_opts[0], 0, 3)
	_opts[1] = clampi(_opts[1], 0, 2)
	_opts[2] = clampi(_opts[2], 0, 2)
	_opts[3] = clampi(_opts[3], 0, 2)
	_opts[4] = clampi(_opts[4], 0, 3)
	_opts[5] = clampi(_opts[5], 0, 1)
	_opts[6] = clampi(_opts[6], 0, FrontEndData.SOUND_TEST_COUNT - 1)
	if _opts[0] == 0:
		_opts[2] = 0


func _save_settings() -> void:
	Settings.set_value("fe_options", _opts.duplicate())
	Settings.set_value("fe_scores", _scores.duplicate(true))


## What the game needs from the option screen.
func game_options() -> Dictionary:
	var one_up: Array = ONE_UP[_opts[4]]
	return {
		"difficulty": _opts[0], "lives": 3 + _opts[1], "teammode": _opts[2], "xtra": _opts[3],
		"one_up": one_up[0], "one_up_repeat": one_up[1], "control": _opts[5],
	}


# ---- display helpers ---------------------------------------------------------------------------------
func _apply_aspect() -> void:
	if _arc == null:
		return
	if _widescreen and size.y > 0.0:
		_arc.ratio = size.x / size.y
	else:
		_arc.ratio = 4.0 / 3.0


func _push_indices() -> void:
	_idx_img.set_data(W, H, false, Image.FORMAT_R8, _idx)
	_idx_tex.update(_idx_img)


func _push_palette() -> void:
	for i in 32:
		var w := _fader.cur[i]
		_pal_img.set_pixel(i, 0, Color8(((w >> 8) & 15) * 17, ((w >> 4) & 15) * 17, (w & 15) * 17))
	_pal_tex.update(_pal_img)


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
		if is_instance_valid(_toast):
			_toast.visible = false)


## Fades the first `count` colours to `words` from black.
func _fade_in(words: PackedInt32Array, count: int) -> void:
	for k in 32:
		_fader.set_colour(k, 0)
	_fader.fade_to(words, 0, count)
	_push_palette()


# ---- audio -------------------------------------------------------------------------------------------
func _music(level: int, song: int) -> void:
	if _audio_level != level:
		_audio.stop()
		if _audio.start(_disks, level):
			_audio_level = level
		else:
			_audio_level = -1
			return
	_audio.song(song)


# ---- attract loop ------------------------------------------------------------------------------------
func _enter_attract(first: bool) -> void:
	_mode = Mode.ATTRACT
	_page = -1
	_page_t = 180
	_page_on = false
	_strip.fill(0)
	_music(0, 0 if first else 1)
	_scene = -1
	_start_scene(0)


func _strip_visible() -> bool:
	return _scene > 0


func _start_scene(i: int) -> void:
	_scene = i
	var def: Dictionary = SCENES[i]
	_fading_out = false
	_idx.fill(0)
	match def["id"]:
		"title":
			FrontEndData.planar_to_indexed(_data.picture(FrontEndData.PIC_TITLE), 0, 40, 256, 4, 0x2800,
					_idx, W, 0, 0)
		"castle": _place_picture(FrontEndData.PIC_CASTLE)
		"sorcerer": _place_picture(FrontEndData.PIC_SORCERER)
		"cabin": _place_picture(FrontEndData.PIC_CABIN)
		"woman": _place_picture(FrontEndData.PIC_WOMAN)
		"hero":
			var frames := _data.picture(FrontEndData.PIC_HERO)
			_hero_screens.clear()
			for f in 6:
				var scr := PackedByteArray()
				scr.resize(W * H)
				FrontEndData.planar_to_indexed(frames, f * 12288, 24, 128, 4, 0xC00, scr, W, PIC_X, PIC_Y)
				_hero_screens.append(scr)
			_hero_frame = 0
			_idx = _hero_screens[0].duplicate()
	if _strip_visible():
		_strip_to_indices()
	_push_indices()
	_fade_in(_data.palette(def["pal"]), 16)
	_scene_t = def["frames"]


func _place_picture(def: Array) -> void:
	FrontEndData.planar_to_indexed(_data.picture(def), 0, 24, 128, 4, 0xC00, _idx, W, PIC_X, PIC_Y)


func _strip_to_indices() -> void:
	for y in STRIP_ROWS:
		if STRIP_Y + y >= H:
			break
		var base := (STRIP_Y + y) * W
		for xb in 40:
			var b: int = _strip[y * 40 + xb]
			for k in 8:
				_idx[base + xb * 8 + k] = TEXT_IDX if (b & (0x80 >> k)) else 0


func _tick_attract() -> void:
	_story_tick()
	if _fading_out:
		_gap_t -= 1
		if _gap_t <= 0:
			_start_scene((_scene + 1) % SCENES.size())
		return
	if SCENES[_scene]["id"] == "hero" and _tick_count % 8 == 0:
		_hero_frame = (_hero_frame + 1) % 6
		_idx = _hero_screens[_hero_frame].duplicate()
		_strip_to_indices()
		_push_indices()
	_scene_t -= 1
	if _scene_t <= 0:
		_fader.fade_to(PackedInt32Array(), 0, 16)
		_fading_out = true
		_gap_t = GAP_FRAMES


## Story text strip: a page is drawn, its colour fades in, stays for the page time, fades out, then a
## short blank gap before the next page (the cycle of the original's slide routine). The strip is
## only visible on the story pictures, not on the title.
func _story_tick() -> void:
	_page_t -= 1
	if _page_t >= 0:
		return
	if not _page_on:
		_page = mini(_page + 1, _pages.size() - 1)
		var pg: Dictionary = _pages[_page]
		_page_t = pg["frames"]
		_strip.fill(0)
		_data.draw_text(_strip, 0, 0, pg["text"])
		if _strip_visible():
			_strip_to_indices()
			_push_indices()
		_fader.fade_colour(TEXT_IDX, TEXT_COLOUR)
		_page_on = true
	else:
		_fader.fade_colour(TEXT_IDX, 0)
		_page_t = 40
		_page_on = false


# ---- input -------------------------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	var key: InputEventKey = event
	if not key.echo:
		match key.keycode:
			KEY_F2:
				_widescreen = not _widescreen
				Settings.set_value("widescreen", _widescreen)
				_apply_aspect()
				_show_toast("WIDESCREEN (stretched)" if _widescreen else "ORIGINAL 4:3")
				return
			KEY_F11:
				var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full
						else DisplayServer.WINDOW_MODE_FULLSCREEN)
				return
	match _mode:
		Mode.ATTRACT:
			if key.echo:
				return
			if key.keycode == KEY_ESCAPE:
				quit_requested.emit()
			elif _is_fire(key):
				if _scene == 0:
					_goto(_enter_options)
				else:
					_goto(func() -> void: _enter_attract(false))
		Mode.OPTIONS:
			_options_key(key)
		Mode.SCORES:
			if not key.echo and (_is_fire(key) or key.keycode == KEY_ESCAPE):
				_goto(func() -> void: _enter_attract(false))
		Mode.NAME:
			_name_key(key)


static func _is_fire(key: InputEventKey) -> bool:
	return key.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_CTRL]


# ---- transitions ---------------------------------------------------------------------------------------
func _goto(cb: Callable) -> void:
	_mode = Mode.TRANSITION
	_fader.fade_to(PackedInt32Array(), 0, 17)
	_trans_t = 34
	_trans_cb = cb


# ---- options -------------------------------------------------------------------------------------------
func _clear_planes() -> void:
	_p0.resize(40 * H)
	_p1.resize(40 * H)
	_p0.fill(0)
	_p1.fill(0)


func _enter_options() -> void:
	_mode = Mode.OPTIONS
	_sel = 7
	_on_save = false
	_clear_planes()
	_data.draw_text(_p0, 4, TABLE_Y, _data.cstr(FrontEndData.OPTION_TEXT))
	_data.draw_text(_p1, OPT_X, OPT_Y, _data.cstr(FrontEndData.OPTION_VALUES))
	for i in 6:
		_draw_option(i)
	_draw_sound()
	_draw_cursor(true)
	_compose_planes(0, H)
	_push_indices()
	_fade_in(_data.palette(FrontEndData.PAL_OPTIONS, 4), 4)


## Two 1-bit planes -> colour index 0..3 (plane 0 = green, plane 1 = blue, both = white).
func _compose_planes(y0: int, y1: int) -> void:
	for y in range(y0, y1):
		for xb in 40:
			var a: int = _p0[y * 40 + xb]
			var b: int = _p1[y * 40 + xb]
			var base := y * W + xb * 8
			for k in 8:
				var m := 0x80 >> k
				_idx[base + k] = (1 if (a & m) else 0) | (2 if (b & m) else 0)


func _redraw_rows(y_from: int, y_to: int) -> void:
	_compose_planes(y_from, y_to)
	_push_indices()


## Only "level" and "1up" are drawn into both planes (white); the other lines in plane 0, which turns the
## selected word white against the light blue list of alternatives in plane 1.
func _draw_option(i: int) -> void:
	var strs: Array = _opt_strings[i]
	var s: String = strs[_opts[i]]
	var y := OPT_Y + 16 * i
	_data.draw_text(_p0, OPT_X, y, s)
	if i == 0 or i == 4:
		_data.draw_text(_p1, OPT_X, y, s)


func _draw_sound() -> void:
	var y := OPT_Y + 16 * 6
	var n: int = _opts[6]
	var digits := "%02d" % n
	var nm: String = _sounds[n]["name"]
	_data.draw_text(_p0, 21, y, digits)
	_data.draw_text(_p1, 21, y, digits)
	_data.draw_text(_p0, 24, y, nm)
	_data.draw_text(_p1, 24, y, nm)


func _draw_cursor(on: bool) -> void:
	var col := SAVE_COL if _on_save else START_COL
	_data.draw_char(_p0, col, OPT_Y + 16 * _sel, 0x3E if on else 0x20)


func _options_key(key: InputEventKey) -> void:
	if key.keycode == KEY_ESCAPE and not key.echo:
		_goto(func() -> void: _enter_attract(false))
		return
	match key.keycode:
		KEY_UP:
			if not _on_save:
				_move_cursor(-1)
		KEY_DOWN:
			if not _on_save:
				_move_cursor(1)
		KEY_LEFT:
			_change(-1)
		KEY_RIGHT:
			_change(1)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			# developer shortcut: jump straight into a level
			if not key.echo:
				_launch(key.keycode - KEY_0)
		_:
			if _is_fire(key) and not key.echo:
				_fire()


func _move_cursor(d: int) -> void:
	_draw_cursor(false)
	var old_y := OPT_Y + 16 * _sel
	_sel = (_sel + d + 8) % 8
	_draw_cursor(true)
	var y := OPT_Y + 16 * _sel
	_redraw_rows(mini(old_y, y), maxi(old_y, y) + 8)


## Left / right on the current line (the original's per-line handlers).
func _change(d: int) -> void:
	var y0 := OPT_Y + 16 * _sel
	if _sel == 7:
		_draw_cursor(false)
		_on_save = d > 0
		_draw_cursor(true)
		_redraw_rows(y0, y0 + 8)
		return
	match _sel:
		0:
			_opts[0] = (_opts[0] + d) & 3
			if _opts[0] == 0:
				_opts[2] = 0           # practice is single player
				_draw_option(2)
				_redraw_rows(OPT_Y + 32, OPT_Y + 40)
		1:
			_opts[1] = posmod(_opts[1] + d, 3)
		2:
			_opts[2] = 0 if _opts[0] == 0 else posmod(_opts[2] + d, 3)
		3:
			_opts[3] = posmod(_opts[3] + d, 3)
		4:
			_opts[4] = posmod(_opts[4] + d, 4)
		5:
			_opts[5] = posmod(_opts[5] + d, 2)
		6:
			_opts[6] = posmod(_opts[6] + d, FrontEndData.SOUND_TEST_COUNT)
	if _sel == 6:
		_draw_sound()
	else:
		_draw_option(_sel)
	_redraw_rows(y0, y0 + 8)


func _fire() -> void:
	if _sel == 6:
		_play_sound_test()
	elif _sel == 7:
		if _on_save:
			_save_settings()
			_flash_saved()
		else:
			_launch(1)


func _flash_saved() -> void:
	var y := OPT_Y + 16 * 7
	_data.draw_text(_p0, 30, y, "saved")
	_redraw_rows(y, y + 8)
	_saved_flash = 100


func _play_sound_test() -> void:
	var n: int = _opts[6]
	var e: Dictionary = _sounds[n]
	if n == 0:
		_audio.song(-1)
		return
	var module: int = e["module"]
	var level := 1
	if module >= 6:
		level = module - 5
	elif _audio_level >= 1:
		level = _audio_level         # shared songs (game over, ...) play from the module that is loaded
	_music(level, e["song"])


func _launch(level: int) -> void:
	_save_settings()
	_audio.stop()
	_audio_level = -1
	var o := game_options()
	o["level"] = level
	start_game.emit(o)


# ---- high scores / name entry ----------------------------------------------------------------------------
func _show_result(score: int, difficulty: int) -> void:
	_new_score = {"score": score, "difficulty": difficulty}
	_entry_rank = -1
	if score > 0:
		for i in 5:
			if score > _scores[i]["score"]:
				_entry_rank = i
				break
	_music(0, 1)
	if _entry_rank >= 0:
		_entry_name = ""
		_enter_name()
	else:
		_enter_scores()


func _score_line(i: int, name_override: String = "") -> String:
	var e: Dictionary = _scores[i]
	var nm: String = e["name"] if name_override == "" else name_override
	nm = (nm + "          ").substr(0, 10)
	var sc := str(e["score"]).lpad(6, " ")
	var diff := _data.difficulty_name(clampi(e["difficulty"], 0, 3))
	return "%d  %s %s  %s" % [i + 1, nm, sc, diff]


func _draw_scores(header: String, rank: int, name_override: String) -> void:
	_clear_planes()
	var text := header + "\r\r"
	for i in 5:
		text += _score_line(i, name_override if i == rank else "") + "\r\r"
	_data.draw_text(_p0, 4, TABLE_Y, text)
	if rank >= 0:
		_data.draw_text(_p1, 4, TABLE_Y + 16 + rank * 16, _score_line(rank, name_override))
	_compose_planes(0, H)
	_push_indices()


func _enter_scores() -> void:
	_mode = Mode.SCORES
	_draw_scores("       top five heroes", _entry_rank, "")
	_fade_in(_data.palette(FrontEndData.PAL_OPTIONS, 4), 4)


func _enter_name() -> void:
	_mode = Mode.NAME
	_cursor_t = 0
	_redraw_name()
	_fade_in(_data.palette(FrontEndData.PAL_OPTIONS, 4), 4)


func _redraw_name() -> void:
	var blink := (_cursor_t / 12) % 2 == 0 and _entry_name.length() < 10
	_draw_scores(" new hero! enter your name", _entry_rank, _entry_name + ("_" if blink else ""))


func _name_key(key: InputEventKey) -> void:
	if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		if key.echo:
			return
		var nm := _entry_name.strip_edges()
		if nm == "":
			nm = "anonymous"
		_scores.insert(_entry_rank, {"score": _new_score["score"], "name": nm.substr(0, 10),
				"difficulty": _new_score["difficulty"]})
		_scores.resize(5)
		_save_settings()
		_goto(_enter_scores)
		return
	if key.keycode == KEY_BACKSPACE:
		if _entry_name.length() > 0:
			_entry_name = _entry_name.substr(0, _entry_name.length() - 1)
			_redraw_name()
		return
	var u := key.unicode
	if u >= 0x20 and u < 0x7F and _entry_name.length() < 10:
		var c := char(u).to_lower()
		if FrontEndData.glyph_column(c.unicode_at(0)) >= 0:
			_entry_name += c
			_redraw_name()


# ---- main loop -----------------------------------------------------------------------------------------
func _physics_process(_delta: float) -> void:
	_tick_count += 1
	match _mode:
		Mode.ATTRACT:
			_tick_attract()
		Mode.TRANSITION:
			_trans_t -= 1
			if _trans_t <= 0:
				var cb := _trans_cb
				_trans_cb = Callable()
				_mode = Mode.ATTRACT
				cb.call()
		Mode.OPTIONS:
			if _saved_flash > 0:
				_saved_flash -= 1
				if _saved_flash == 0:
					var y := OPT_Y + 16 * 7
					_data.draw_text(_p0, 30, y, "     ")
					_redraw_rows(y, y + 8)
		Mode.NAME:
			_cursor_t += 1
			if _cursor_t % 12 == 0:
				_redraw_name()
	if _fader.step():
		_push_palette()
