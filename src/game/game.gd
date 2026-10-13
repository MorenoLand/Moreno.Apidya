class_name Game
extends Control
## One level of Apidya. All data comes from LevelData (decoded from the user's own disk images).
## Coordinates: "raw" coordinates are the original game's object coordinates (x 0..~350, y 0..240 inside
## the playfield). Screen x = raw x - X_OFFSET, screen y = raw y + FIELD_Y.

signal exited

const VIEW_W := 320
const VIEW_H := 256
const FIELD_Y := 8              # viewport row of the first playfield line (HUD strip above)
const FIELD_H := 240
const LINE_OFFSET := 40         # Amiga video line shown on viewport row 0
const X_OFFSET := 14
const SCROLL_STEP := 0.5        # px per 50 Hz tick
const PLAYER_X_MIN := 20
const PLAYER_X_MAX := 300
const PLAYER_Y_MIN := 3
const PLAYER_Y_MAX := 212
const FIRE_REPEAT := 6          # ticks between volleys while the button is held
const METER := ["SPD", "BMB", "SHT", "MSL", "WAV", "OPT", "SHD", "SLW"]

# sound effect numbers used by the original (from the call sites of its sound routine)
const SFX_ENEMY_FIRE := 7
const SFX_EXPLODE := 14
const SFX_PLAYER_DIE := 30
const SFX_PICKUP := 0x1D
const SFX_USE := 0x14
const SFX_DENIED := 0x1E
const SONG_LEVEL := 0
const SONG_LEVEL_END := 6

var _disks: DiskSet
var _level_no := 1
var _level: LevelData

var _vp: SubViewport
var _world: Node2D
var _mat: ShaderMaterial
var _mat_flash: ShaderMaterial
var _bg: Sprite2D
var _player_spr: Sprite2D
var _hud: Label
var _meter_label: Label
var _msg: Label
var _tex_cache := {}

var scroll := 0.0
var scroll_locked := false     # a guardian holds the scroll ($7BAC)
var phase_event := 0           # $7B50: guardian defeated / level section done
var _col := -1
var _wave_idx := 0
var _enemies: Array[Enemy] = []
var _bullets: Array[Dictionary] = []     # enemy bullets {x,y,vx,vy,big,spr}
var _explosions: Array[Dictionary] = []
var _groups: Array = []                  # formation group slots (null or dictionary)
var _items: Array[Dictionary] = []       # power-up capsules {x,y,spr}
var _ps := PlayerState.new()
var _weapons: Weapons
var _tick := 0

# player state (raw coordinates)
var px := 40
var py := 100
var _vdir := 0
var _anim := 0
var _anim_t := 0
var _lives := 3
var _options := {}
var _score := 0
var _invuln := 0
var _fire_t := 0
var _fire_was_down := false
var _dead_t := 0
var _finished := false
var rng := RandomNumberGenerator.new()
var _audio: AudioManager
var _arc: AspectRatioContainer
var _widescreen := false
var _toast: Label
var _xtra_latch := false
var _prev_px := 0
var _prev_py := 0


## `options` comes from the front end's option screen (see FrontEnd.game_options).
func setup(disks: DiskSet, level_no: int, options: Dictionary = {}) -> void:
	_disks = disks
	_level_no = level_no
	_options = options
	_lives = int(options.get("lives", 3))


func get_score() -> int:
	return _score


func _ready() -> void:
	rng.seed = 1992
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_level = LevelData.load_level(_disks, _level_no)

	var back := ColorRect.new()
	back.color = Color.BLACK
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)

	var arc := AspectRatioContainer.new()
	arc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arc.ratio = 4.0 / 3.0
	add_child(arc)
	_arc = arc

	_vp = SubViewport.new()
	_vp.size = Vector2i(VIEW_W, VIEW_H)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_vp)

	var rect := TextureRect.new()
	rect.texture = _vp.get_texture()
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	arc.add_child(rect)

	_world = Node2D.new()
	_vp.add_child(_world)
	var vp_back := ColorRect.new()
	vp_back.color = Color.BLACK
	vp_back.size = Vector2(VIEW_W, VIEW_H)
	_world.add_child(vp_back)

	var shader := load("res://shaders/amiga_indexed.gdshader") as Shader
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("palette", ImageTexture.create_from_image(_level.line_palette))
	_mat.set_shader_parameter("line_offset", LINE_OFFSET)
	_mat_flash = _mat.duplicate() as ShaderMaterial
	_mat_flash.set_shader_parameter("brightness", 2.2)

	_bg = Sprite2D.new()
	_bg.centered = false
	_bg.region_enabled = true
	_bg.texture = ImageTexture.create_from_image(_level.bg_image)
	_bg.material = _mat
	_bg.position = Vector2(0, FIELD_Y)
	_world.add_child(_bg)

	_player_spr = Sprite2D.new()
	_player_spr.centered = false
	_player_spr.material = _mat
	_world.add_child(_player_spr)

	_weapons = Weapons.new()
	_world.add_child(_weapons)
	_weapons.setup(_level, _ps, _mat, FIELD_Y)
	_weapons.sound.connect(_on_weapon_sound)
	_weapons.enemy_hit.connect(_on_enemy_hit)

	_hud = Label.new()
	_hud.add_theme_font_size_override("font_size", 8)
	_hud.position = Vector2(2, -2)
	_vp.add_child(_hud)
	_meter_label = Label.new()
	_meter_label.add_theme_font_size_override("font_size", 8)
	_meter_label.position = Vector2(150, -2)
	_vp.add_child(_meter_label)
	_msg = Label.new()
	_msg.add_theme_font_size_override("font_size", 10)
	_msg.position = Vector2(80, 110)
	_vp.add_child(_msg)
	_update_hud()

	_toast = Label.new()
	_toast.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toast.visible = false
	add_child(_toast)
	resized.connect(_apply_aspect)
	_set_widescreen(bool(Settings.get_value("widescreen", false)), false)

	_audio = AudioManager.new()
	add_child(_audio)
	if _audio.start(_disks, _level_no):
		_audio.song(SONG_LEVEL)


func _exit_tree() -> void:
	if _audio != null:
		_audio.stop()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ESCAPE:
			exited.emit()
		KEY_F2:
			_set_widescreen(not _widescreen, true)
			_show_toast("WIDESCREEN (stretched)" if _widescreen else "ORIGINAL 4:3")
		KEY_F11:
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


## F2: false = original 4:3 picture with bars, true = stretched to fill the whole window.
func _set_widescreen(on: bool, save: bool) -> void:
	_widescreen = on
	if save:
		Settings.set_value("widescreen", on)
	_apply_aspect()


func _apply_aspect() -> void:
	if _arc == null:
		return
	if _widescreen and size.y > 0.0:
		_arc.ratio = size.x / size.y
	else:
		_arc.ratio = 4.0 / 3.0


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
		if is_instance_valid(_toast):
			_toast.visible = false)


func _tex(img: Image) -> ImageTexture:
	var k := img.get_instance_id()
	if not _tex_cache.has(k):
		_tex_cache[k] = ImageTexture.create_from_image(img)
	return _tex_cache[k]


func _update_hud() -> void:
	_hud.text = "L%d  %06d  x%d" % [_level_no, _score, _lives]
	var t := ""
	for i in METER.size():
		t += ("[%s]" if _ps.bar == i + 1 else " %s ") % METER[i]
	_meter_label.text = t


# ------------------------------------------------------------------------------------------------
func _physics_process(_delta: float) -> void:
	if _finished:
		return
	_tick += 1
	Enemy.phase_a = [0, 1, 2, 1][_tick & 3]
	Enemy.phase_b = [1, 2, 1, 0][_tick & 3]
	if not scroll_locked:
		scroll += SCROLL_STEP
	var new_col := int(scroll) / 16
	var maxscroll := float(_level.cols * 16 - VIEW_W)
	if scroll >= maxscroll:
		scroll = maxscroll
		_finish("LEVEL COMPLETE")
	_bg.region_rect = Rect2(int(scroll), 0, VIEW_W, FIELD_H)
	while new_col > _col:
		_col += 1
		_spawn_wave(_col)

	_tick_groups()
	_update_player()
	_update_enemies()
	_weapons.tick(px, py, scroll, _enemies, px != _prev_px or py != _prev_py)
	_prev_px = px
	_prev_py = py
	_reap_dead()
	_update_items()
	_update_bullets()
	_update_explosions()
	_collide()
	_update_hud()


func _finish(text: String) -> void:
	_finished = true
	if _audio != null and text == "LEVEL COMPLETE":
		_audio.song(SONG_LEVEL_END)
	elif _audio != null:
		_audio.fade(0x30000)
	_msg.text = text + "\n\nPress ESC"


# ---- enemies and formations --------------------------------------------------------------------
func _spawn_wave(col: int) -> void:
	var waves := _level.waves
	while _wave_idx < waves.size() and waves[_wave_idx]["col"] == 0:
		_wave_idx += 1
	while _wave_idx < waves.size() and waves[_wave_idx]["col"] == col:
		var w: Dictionary = waves[_wave_idx]
		_wave_idx += 1
		if w["group"]:
			_start_group(w)
		else:
			_spawn_enemy(w, -1)


func _spawn_enemy(w: Dictionary, group_slot: int) -> Enemy:
	var e := Enemy.new()
	e.init_from_wave(w, _level, scroll, group_slot)
	if e.type == 4 or e.type == 5:
		e.handler = Handlers.lookup(_level_no, e.handler_addr)
	e.spr = Sprite2D.new()
	e.spr.centered = false
	e.spr.material = _mat
	_world.add_child(e.spr)
	_enemies.append(e)
	return e


func _start_group(w: Dictionary) -> void:
	var g := {"entries": _level.decode_formation(w["list"]), "i": 0, "timer": 0, "alive": 0,
		"killed": 0, "required": w["required"], "hold": w["hold"]}
	for i in _groups.size():
		if _groups[i] == null:
			_groups[i] = g
			return
	_groups.append(g)


## The original's group routine ($3B60): every tick the group timer advances and the entry whose
## delay it reaches is spawned; a group whose list ended is freed once all of its enemies are gone.
func _tick_groups() -> void:
	for idx in _groups.size():
		var g: Variant = _groups[idx]
		if g == null or g["hold"] != 0:
			continue
		var entries: Array = g["entries"]
		if g["i"] >= entries.size():
			if g["alive"] <= 0:
				_groups[idx] = null
			continue
		g["timer"] += 1
		if g["timer"] >= entries[g["i"]]["delay"]:
			_spawn_enemy(entries[g["i"]], idx)
			g["alive"] += 1
			g["i"] += 1


func _enemy_gone(e: Enemy, killed: bool) -> void:
	if e.group < 0 or e.group >= _groups.size() or _groups[e.group] == null:
		return
	var g: Dictionary = _groups[e.group]
	g["alive"] -= 1
	if killed:
		g["killed"] += 1
		if g["required"] > 0 and g["killed"] == g["required"]:
			g["killed"] = 0
			drop_item(e.x, e.y)


func drop_item(x: float, y: float) -> void:
	var spr := Sprite2D.new()
	spr.centered = false
	spr.material = _mat
	spr.texture = _tex(_level.item_img)
	_world.add_child(spr)
	_items.append({"x": x, "y": y, "spr": spr})


func _update_enemies() -> void:
	for e in _enemies:
		if e.dead:
			continue
		e.tick(self)
		if e.dead:
			continue
		e.update_sprite(self, FIELD_Y, X_OFFSET, _tex)
		e.spr.material = _mat_flash if e.flash > 0 else _mat


## Removes dead enemies (destroyed or gone) and does the group bookkeeping.
func _reap_dead() -> void:
	var keep: Array[Enemy] = []
	for e in _enemies:
		if e.dead:
			_enemy_gone(e, e.killed)
			if e.killed and e.on_death.is_valid():
				e.on_death.call(self, e)
			if e.killed and not e.dying:
				explode(e.x + 4.0, e.y + 4.0)
			e.spr.queue_free()
			for part in e.parts:
				part.queue_free()
		else:
			keep.append(e)
	_enemies = keep


func _on_enemy_hit(e: Enemy, killed: bool) -> void:
	if killed:
		_score += e.score
		_audio.sfx(SFX_EXPLODE)


func _on_weapon_sound(effect: int) -> void:
	_audio.sfx(effect)


# ---- items / meter ----------------------------------------------------------------------------
func _update_items() -> void:
	var keep: Array[Dictionary] = []
	for it in _items:
		if not scroll_locked:
			it["x"] -= SCROLL_STEP
		if it["x"] < -20.0:
			it["spr"].queue_free()
			continue
		# pick up: the capsule's position inside [px-8, px+32] x [py-6, py+24]
		if _dead_t == 0 and it["x"] >= px - 8 and it["x"] <= px + 32 and it["y"] >= py - 6 and it["y"] <= py + 24:
			_ps.pickup()
			_audio.sfx(SFX_PICKUP)
			it["spr"].queue_free()
			continue
		it["spr"].position = Vector2(it["x"] - X_OFFSET, it["y"] + FIELD_Y)
		keep.append(it)
	_items = keep


func _use_meter() -> void:
	match _ps.activate():
		PlayerState.Result.USED:
			_audio.sfx(SFX_USE)
		PlayerState.Result.DENIED:
			_audio.sfx(SFX_DENIED)


# ---- player -------------------------------------------------------------------------------------
func _update_player() -> void:
	if _dead_t > 0:
		_dead_t -= 1
		_player_spr.visible = (_dead_t / 4) % 2 == 0 and _dead_t < 40
		if _dead_t == 0:
			if _lives <= 0:
				_finish("GAME OVER")
				return
			_invuln = 100
			px = 40
			py = 100
		return
	var dx := int(Input.is_action_pressed("move_right")) - int(Input.is_action_pressed("move_left"))
	var dy := int(Input.is_action_pressed("move_down")) - int(Input.is_action_pressed("move_up"))
	px = clampi(px + dx * _ps.speed, PLAYER_X_MIN, PLAYER_X_MAX)
	py = clampi(py + dy * _ps.speed, PLAYER_Y_MIN, PLAYER_Y_MAX)
	_vdir = 0
	if dy < 0:
		_vdir = 1       # up   -> variant 2
	elif dy > 0:
		_vdir = -1      # down -> variant 1
	_anim_t += 1
	if _anim_t >= 2:
		_anim_t = 0
		_anim = (_anim + 1) & 3
	var variant := 0 if _vdir == 0 else (2 if _vdir > 0 else 1)
	var frames: Array = _level.player_frames[variant] if variant < _level.player_frames.size() else []
	if frames.is_empty():
		frames = _level.player_frames[0]
	var fr: Dictionary = frames[_anim % frames.size()]
	_player_spr.texture = _tex(fr["img"])
	_player_spr.position = Vector2(px - X_OFFSET, py + FIELD_Y + fr["yoff"])
	_player_spr.visible = true
	if _invuln > 0:
		_invuln -= 1
		_player_spr.visible = (_invuln / 3) % 2 == 0

	# firing: tap or hold (repeats), holding also charges the blast that is let go on release
	var held := Input.is_action_pressed("fire")
	if held:
		_fire_t -= 1
		if not _fire_was_down or _fire_t <= 0:
			if _weapons.fire(px, py):
				_fire_t = FIRE_REPEAT
			else:
				_fire_t = 2
	_weapons.hold_fire(held, px, py)
	_fire_was_down = held

	# power-up meter: second button, or by itself in "auto" mode
	var xtra := Input.is_action_pressed("xtra")
	if xtra and not _xtra_latch:
		_use_meter()
	_xtra_latch = xtra
	if int(_options.get("xtra", 0)) == 0 and _ps.auto_wants():
		_use_meter()


# ---- engine services used by the enemy handlers ------------------------------------------------------
func sfx(n: int) -> void:
	_audio.sfx(n)


func difficulty() -> int:
	return int(_options.get("difficulty", 2))


## The original's $7B5C: toggles 0 / 1 every tick, so "x -= $7B5C" scrolls half a pixel per tick.
func scroll_step() -> int:
	return 0 if scroll_locked else (_tick & 1)


func _vel_scale(v: float) -> float:
	var d := difficulty()
	if d < 2:
		return v * 0.75
	if d > 2:
		return v * 1.5
	return v


func _add_bullet(x: float, y: float, vx: float, vy: float, big: bool = false) -> void:
	var s := Sprite2D.new()
	s.centered = false
	s.material = _mat
	_world.add_child(s)
	_bullets.append({"x": x, "y": y, "vx": vx, "vy": vy, "big": big, "spr": s})


## `$535A`: shot aimed at the player, 2 px per tick (practice / easy: not at point blank).
func fire_aimed(x: float, y: float) -> void:
	if y < 0.0:
		return
	if difficulty() < 2 and absf(x - px) + absf(y - py) <= 0x5A:
		return
	var dx := float(px + 8) - x
	var dy := float(py + 10) - y
	var len := sqrt(dx * dx + dy * dy)
	if len < 0.5:
		return
	_add_bullet(x, y, _vel_scale(dx / len * 2.0), _vel_scale(dy / len * 2.0))
	sfx(SFX_ENEMY_FIRE)


## `$53E4`: shot with velocity (d2, d3) given in the original's 16.16 units (0x80000 = 4 px per tick).
func fire_vel(x: float, y: float, d2: int, d3: int) -> void:
	if (d2 >> 9) == 0 and (d3 >> 9) == 0:
		return
	_add_bullet(x, y, _vel_scale(float(d2) / 131072.0), _vel_scale(float(d3) / 131072.0))


const DIR_DX1 := [0, 0, 1, 1, 1, 1, 1, 0, 0, 0, -1, -1, -1, -1, -1, 0]
const DIR_DY1 := [-1, -1, -1, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, -1, -1]
const DIR_DX2 := [0, 1, 2, 2, 2, 2, 2, 1, 0, -1, -2, -2, -2, -2, -2, -1]
const DIR_DY2 := [-2, -2, -2, -1, 0, 1, 2, 2, 2, 2, 2, 1, 0, -1, -2, -2]


## `$531E`: bullet of the given type word (low 5 bits = kind, high byte = direction index * 2).
func fire_dir(x: float, y: float, word: int) -> void:
	var kind := word & 0x1F
	var idx := ((word >> 8) & 0x1F) >> 1
	match kind:
		1:
			_add_bullet(x, y, DIR_DX1[idx], DIR_DY1[idx])
		3:
			_add_bullet(x, y, -4.0, -4.0, true)
		_:
			_add_bullet(x, y, DIR_DX2[idx], DIR_DY2[idx])


## `$441A`: a falling object that follows the level's "ball" script.
func spawn_ball(x: float, y: float) -> void:
	var w := {"type": 2, "flags": 0, "x": int(x), "y": int(y), "hp": 127, "frame": 0,
		"script": _level_def_value("ball_script"), "p6": 0, "p7": 0, "score_bcd": 0,
		"fire_timer": 255, "fire_reload": 255, "handler": 0, "p11": 0}
	_spawn_enemy(w, -1)


## `$446C`: heavy projectile aimed at the player (4 px per tick), an enemy with 127 hit points.
func spawn_heavy(x: float, y: float) -> void:
	if difficulty() < 2 and absf(x - px) + absf(y - py) <= 0x5A:
		return
	var dx := float(px + 8) - x
	var dy := float(py + 10) - y
	var len := sqrt(dx * dx + dy * dy)
	if len < 0.5:
		return
	var w := {"type": 4, "flags": 0, "x": int(x), "y": int(y), "hp": 127, "frame": 0x27, "script": 0,
		"p6": 0, "p7": 0, "score_bcd": 0, "fire_timer": 255, "fire_reload": 255, "handler": 0, "p11": 0}
	var e := _spawn_enemy(w, -1)
	e.handler = Callable(self, "_heavy_handler")
	e.vx = _vel_scale(dx / len * 4.0)
	e.vy = _vel_scale(dy / len * 4.0)


## An enemy built from code: handler-driven, drawn by the handler through draw_part.
func spawn_native(x: float, y: float, hp: int, frame: int, handler: Callable, hit_w: int, hit_h: int) -> Enemy:
	var w := {"type": 4, "flags": 0, "x": int(x), "y": int(y), "hp": hp, "frame": frame, "script": 0,
		"p6": 0, "p7": 0, "score_bcd": 0, "fire_timer": 255, "fire_reload": 255, "handler": 0, "p11": 0}
	var e := _spawn_enemy(w, -1)
	e.handler = handler
	e.set_hitbox(hit_w, hit_h)
	return e


## Extra sprite of an enemy (guardian pieces, thrown balls) at raw position (x, y).
func draw_part(e: Enemy, idx: int, img: Image, x: float, y: float) -> void:
	while e.parts.size() <= idx:
		var s := Sprite2D.new()
		s.centered = false
		s.material = _mat
		_world.add_child(s)
		e.parts.append(s)
	var sp := e.parts[idx]
	sp.texture = _tex(img)
	sp.position = Vector2(x - X_OFFSET, y + FIELD_Y)
	sp.visible = true
	sp.material = _mat_flash if e.flash > 0 else _mat


func level_plane_image(gfx: int, mask: int, w_words: int, rows: int) -> Image:
	return _level.plane_image(gfx, mask, w_words, rows)


## `$5DD4`-style boomerang shot: starts at 4 px per tick, slows down by 0.19 per tick and zig-zags
## vertically between -2 and +2 px per tick.
func fire_boomerang(x: float, y: float, dir: int) -> void:
	var s := Sprite2D.new()
	s.centered = false
	s.material = _mat
	_world.add_child(s)
	_bullets.append({"x": x, "y": y, "vx": 4.0, "vy": 0.0, "big": false, "spr": s, "zig": dir,
		"ax": -float(0x30) / 256.0})


func _heavy_handler(_g: Game, e: Enemy) -> void:
	e.frame = ((_tick >> 2) & 1) + 0x15
	e.x += e.vx
	e.y += e.vy
	if e.x < 0.0 or e.y < 0.0 or e.x > 0x15E or e.y > 0xE0:
		e.dead = true


func _level_def_value(key: String) -> int:
	return int(LevelDefs.LEVELS[_level_no][key])


## `$269E`: small explosion made of the wave shot orbs.
func explode(x: float, y: float) -> void:
	if x > 0x14E or y > 0xEF or x < 0.0 or y < 0.0:
		return
	var s := Sprite2D.new()
	s.centered = false
	s.material = _mat
	_world.add_child(s)
	_explosions.append({"x": x, "y": y, "t": 0, "spr": s})


func _update_explosions() -> void:
	var order := [0, 1, 2, 2, 1, 0]
	var keep: Array[Dictionary] = []
	var orbs: Array = _level.shot_art["wave_b"]
	for ex in _explosions:
		var f: int = ex["t"] / 2
		if f >= order.size():
			ex["spr"].queue_free()
			continue
		var img: Image = orbs[order[f]]
		ex["spr"].texture = _tex(img)
		ex["spr"].position = Vector2(ex["x"] - X_OFFSET, ex["y"] + FIELD_Y + 6 - img.get_height() / 2)
		ex["t"] += 1
		keep.append(ex)
	_explosions = keep


func _update_bullets() -> void:
	var frames: Array = _level.shot_art["eb"]
	var frame_img: Image = frames[(_tick >> 2) & 7]
	var keep: Array[Dictionary] = []
	for b in _bullets:
		if b.has("zig"):
			b["vx"] += b["ax"]
			if b["zig"] != 0:
				b["vy"] += 0.125
				if b["vy"] >= 2.0:
					b["zig"] = 0
			else:
				b["vy"] -= 0.125
				if b["vy"] <= -2.0:
					b["zig"] = 1
		b["x"] += b["vx"]
		b["y"] += b["vy"]
		if b["x"] < 0x10 or b["x"] >= 0x154 or b["y"] < 0 or b["y"] >= 0xE6:
			b["spr"].queue_free()
			continue
		b["spr"].texture = _tex(_level.shot_art["enemy_big"] if b["big"] else frame_img)
		b["spr"].position = Vector2(b["x"] - X_OFFSET, b["y"] + FIELD_Y)
		keep.append(b)
	_bullets = keep


func _collide() -> void:
	if _dead_t > 0 or _invuln > 0:
		return
	# enemies / bullets vs player: rect [px-8, px+16] x [py-4, py+6]
	var l := px - 8
	var r := px + 16
	var t := py - 4
	var b := py + 6
	for e in _enemies:
		if e.hp <= 0 or e.dead:
			continue
		if e.x <= r and e.x + e.hit_w >= l and e.y <= b and e.y + e.hit_h >= t:
			_player_hit()
			return
	for bl in _bullets:
		if bl["x"] <= r and bl["x"] + 6 >= l and bl["y"] <= b and bl["y"] + 3 >= t:
			bl["spr"].queue_free()
			_bullets.erase(bl)
			_player_hit()
			return


func _player_hit() -> void:
	if _ps.shield and _ps.shield_hits > 0:
		_ps.shield_hits -= 1
		if _ps.shield_hits <= 0:
			_ps.shield = false
		_invuln = 40
		return
	_audio.sfx(SFX_PLAYER_DIE)
	_lives -= 1
	_dead_t = 60
	_player_spr.visible = false
	_ps.reset_for_life()
	_update_hud()
