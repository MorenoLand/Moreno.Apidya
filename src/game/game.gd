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
const PLAYER_SPEED := 2
const SHOT_SPEED := 12
const MAX_PLAYER_SHOTS := 2

var _disks: DiskSet
var _level_no := 1
var _level: LevelData

var _vp: SubViewport
var _world: Node2D
var _mat: ShaderMaterial
var _bg: Sprite2D
var _player_spr: Sprite2D
var _hud: Label
var _msg: Label
var _tex_cache := {}

var _scroll := 0.0
var _col := -1
var _wave_idx := 0
var _enemies: Array[Enemy] = []
var _shots: Array[Dictionary] = []       # player shots {x,y,spr}
var _bullets: Array[Dictionary] = []     # enemy bullets {x,y,vx,vy,spr}
var _bullet_tex: ImageTexture

# player state (raw coordinates)
var px := 40
var py := 100
var _vdir := 0
var _anim := 0
var _anim_t := 0
var _lives := 3
var _score := 0
var _invuln := 0
var _fire_cd := 0
var _dead_t := 0
var _finished := false
var _rng := RandomNumberGenerator.new()


func setup(disks: DiskSet, level_no: int) -> void:
	_disks = disks
	_level_no = level_no


func _ready() -> void:
	_rng.seed = 1992
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_level = LevelData.load_level(_disks, _level_no)

	var back := ColorRect.new()
	back.color = Color.BLACK
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)

	var arc := AspectRatioContainer.new()
	arc.set_anchors_preset(Control.PRESET_FULL_RECT)
	arc.ratio = 4.0 / 3.0
	add_child(arc)

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

	var shader := load("res://shaders/amiga_indexed.gdshader") as Shader
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("palette", ImageTexture.create_from_image(_level.line_palette))
	_mat.set_shader_parameter("line_offset", LINE_OFFSET)

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

	# bullet graphic: small bright block (index of the brightest palette colour)
	var bright := 19
	var best := -1.0
	for i in 32:
		var lum := _level.palette[i].r + _level.palette[i].g + _level.palette[i].b
		if lum > best:
			best = lum
			bright = i
	var bimg := Image.create(6, 3, false, Image.FORMAT_LA8)
	for yy in 3:
		for xx in 6:
			bimg.set_pixel(xx, yy, Color(bright / 255.0, bright / 255.0, bright / 255.0, 1.0))
	_bullet_tex = ImageTexture.create_from_image(bimg)

	_hud = Label.new()
	_hud.add_theme_font_size_override("font_size", 8)
	_hud.position = Vector2(2, -2)
	_vp.add_child(_hud)
	_msg = Label.new()
	_msg.add_theme_font_size_override("font_size", 10)
	_msg.position = Vector2(80, 110)
	_vp.add_child(_msg)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		exited.emit()


func _tex(img: Image) -> ImageTexture:
	var k := img.get_instance_id()
	if not _tex_cache.has(k):
		_tex_cache[k] = ImageTexture.create_from_image(img)
	return _tex_cache[k]


func _update_hud() -> void:
	_hud.text = "L%d %s   SCORE %06d   LIVES %d" % [_level_no, _level.name.to_upper(), _score, _lives]


# ------------------------------------------------------------------------------------------------
func _physics_process(_delta: float) -> void:
	if _finished:
		return
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

	_update_player()
	_update_enemies()
	_update_shots()
	_update_bullets()
	_collide()
	_update_hud()


func _finish(text: String) -> void:
	_finished = true
	_msg.text = text + "\n\nPress ESC"


func _spawn_wave(col: int) -> void:
	var waves := _level.waves
	while _wave_idx < waves.size() and waves[_wave_idx]["col"] == 0:
		_wave_idx += 1
	while _wave_idx < waves.size() and waves[_wave_idx]["col"] == col:
		var w: Dictionary = waves[_wave_idx]
		_wave_idx += 1
		if w["decor"]:
			continue
		var e := Enemy.new()
		e.init_from_wave(w, _level, _scroll)
		e.spr = Sprite2D.new()
		e.spr.centered = false
		e.spr.material = _mat
		_world.add_child(e.spr)
		_enemies.append(e)


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
	px = clampi(px + dx * PLAYER_SPEED, PLAYER_X_MIN, PLAYER_X_MAX)
	py = clampi(py + dy * PLAYER_SPEED, PLAYER_Y_MIN, PLAYER_Y_MAX)
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
	# firing
	if _fire_cd > 0:
		_fire_cd -= 1
	if Input.is_action_pressed("fire") and _shots.size() <= MAX_PLAYER_SHOTS - 2 and _fire_cd == 0:
		_fire_cd = 6
		for oy in [10, 22]:
			var s := Sprite2D.new()
			s.centered = false
			s.material = _mat
			s.texture = _bullet_tex
			_world.add_child(s)
			_shots.append({"x": px + 8, "y": py + oy, "spr": s})


func _update_enemies() -> void:
	var keep: Array[Enemy] = []
	for e in _enemies:
		e.tick(_level, px, py, _scroll, _rng)
		if e.dead:
			e.spr.queue_free()
			continue
		e.update_sprite(_level, FIELD_Y, X_OFFSET, _tex)
		if e.want_fire(_rng):
			_enemy_fire(e)
		keep.append(e)
	_enemies = keep


func _enemy_fire(e: Enemy) -> void:
	var sx := e.x + 4.0
	var sy := e.y + 4.0
	var dxp := float(px + 4) - sx
	var dyp := float(py + 10) - sy
	var len := maxf(1.0, sqrt(dxp * dxp + dyp * dyp))
	var s := Sprite2D.new()
	s.centered = false
	s.material = _mat
	s.texture = _bullet_tex
	_world.add_child(s)
	_bullets.append({"x": sx, "y": sy, "vx": dxp / len * 2.0, "vy": dyp / len * 2.0, "spr": s})


func _update_shots() -> void:
	var keep: Array[Dictionary] = []
	for s in _shots:
		s["x"] += SHOT_SPEED
		if s["x"] > 330:
			s["spr"].queue_free()
			continue
		s["spr"].position = Vector2(s["x"] - X_OFFSET, s["y"] + FIELD_Y)
		keep.append(s)
	_shots = keep


func _update_bullets() -> void:
	var keep: Array[Dictionary] = []
	for b in _bullets:
		b["x"] += b["vx"]
		b["y"] += b["vy"]
		if b["x"] < -10 or b["x"] > 340 or b["y"] < -10 or b["y"] > 250:
			b["spr"].queue_free()
			continue
		b["spr"].position = Vector2(b["x"] - X_OFFSET, b["y"] + FIELD_Y)
		keep.append(b)
	_bullets = keep


func _collide() -> void:
	# player shots vs enemies (raw coordinates, as in the original)
	var live_shots: Array[Dictionary] = []
	for s in _shots:
		var hit := false
		for e in _enemies:
			if e.hp <= 0 or e.dead:
				continue
			if s["x"] + 6 >= e.x and s["x"] <= e.x + e.hit_w and s["y"] + 3 >= e.y and s["y"] <= e.y + e.hit_h:
				e.hit(1)
				hit = true
				if e.hp <= 0:
					_score += e.score
				break
		if hit:
			s["spr"].queue_free()
		else:
			live_shots.append(s)
	_shots = live_shots
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
	_lives -= 1
	_dead_t = 60
	_player_spr.visible = false
	_update_hud()
