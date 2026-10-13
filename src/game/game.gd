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

var _scroll := 0.0
var _col := -1
var _wave_idx := 0
var _enemies: Array[Enemy] = []
var _bullets: Array[Dictionary] = []     # enemy bullets {x,y,vx,vy,spr}
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
var _rng := RandomNumberGenerator.new()
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
	_rng.seed = 1992
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
	_scroll += SCROLL_STEP
	var new_col := int(_scroll) / 16
	var max_scroll := float(_level.cols * 16 - VIEW_W)
	if _scroll >= max_scroll:
		_scroll = max_scroll
		_finish("LEVEL COMPLETE")
	_bg.region_rect = Rect2(int(_scroll), 0, VIEW_W, FIELD_H)
	while new_col > _col:
		_col += 1
		_spawn_wave(_col)

	_tick_groups()
	_update_player()
	_update_enemies()
	_weapons.tick(px, py, _scroll, _enemies, px != _prev_px or py != _prev_py)
	_prev_px = px
	_prev_py = py
	_reap_dead()
	_update_items()
	_update_bullets()
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


func _spawn_enemy(w: Dictionary, group_slot: int) -> void:
	var e := Enemy.new()
	e.init_from_wave(w, _level, _scroll, group_slot)
	e.spr = Sprite2D.new()
	e.spr.centered = false
	e.spr.material = _mat
	_world.add_child(e.spr)
	_enemies.append(e)


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
			_drop_item(e.x, e.y)


func _drop_item(x: float, y: float) -> void:
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
		e.tick(_level, px, py, _scroll, _rng)
		if e.dead:
			continue
		e.update_sprite(_level, FIELD_Y, X_OFFSET, _tex)
		e.spr.material = _mat_flash if e.flash > 0 else _mat
		if e.want_fire(_rng):
			_enemy_fire(e)


## Removes dead enemies (destroyed or gone) and does the group bookkeeping.
func _reap_dead() -> void:
	var keep: Array[Enemy] = []
	for e in _enemies:
		if e.dead:
			_enemy_gone(e, e.killed)
			e.spr.queue_free()
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


# ---- enemy bullets ---------------------------------------------------------------------------------
func _enemy_fire(e: Enemy) -> void:
	var sx := e.x + 4.0
	var sy := e.y + 4.0
	var dxp := float(px + 4) - sx
	var dyp := float(py + 10) - sy
	var len := maxf(1.0, sqrt(dxp * dxp + dyp * dyp))
	var s := Sprite2D.new()
	s.centered = false
	s.material = _mat
	_world.add_child(s)
	_bullets.append({"x": sx, "y": sy, "vx": dxp / len * 2.0, "vy": dyp / len * 2.0, "spr": s})
	_audio.sfx(SFX_ENEMY_FIRE)


func _update_bullets() -> void:
	var frames: Array = _level.shot_art["eb"]
	var frame_img: Image = frames[(_tick >> 2) & 7]
	var keep: Array[Dictionary] = []
	for b in _bullets:
		b["x"] += b["vx"]
		b["y"] += b["vy"]
		if b["x"] < -10 or b["x"] > 340 or b["y"] < -10 or b["y"] > 250:
			b["spr"].queue_free()
			continue
		b["spr"].texture = _tex(frame_img)
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
