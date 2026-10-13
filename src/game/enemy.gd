class_name Enemy
extends RefCounted
## One enemy. Behaviour follows the original's updater (types 1, 2/3 and 6+); types 4/5 (boss/native
## handlers) are not ported yet and behave like type 1 (they sit in the scroll with their hit points).

var spr: Sprite2D
var type := 1
var x := 0.0                 # raw coordinates
var y := 0.0
var hp := 1
var score := 0
var frame := 0
var hit_w := 16
var hit_h := 16
var dead := false
var flash := 0

# type 2/3 path state
var _script: Array = []
var _entry := -1
var _repeat := 0
var _steps: Array = []
var _step := 0
var _timer := 0
var _dx := 0
var _dy := 0
# type 6+ polar state
var _polar: Array = []
var _pi := 0
var _ptimer := 0
var _code := 0
# fire
var _fire_reload := 0
var _fire_t := 0
var _world_x := 0.0          # type 1: world x (screen x + scroll)


func init_from_wave(w: Dictionary, level: LevelData, scroll: float) -> void:
	type = w["type"]
	x = float(w["x"])
	y = float(w["y"])
	hp = maxi(1, w["hp"])
	frame = w["frame"]
	score = _bcd(w["score_bcd"])
	_fire_reload = w["fire_reload"] * 2
	_fire_t = _fire_reload
	_world_x = x - 14.0 + scroll
	match type:
		2, 3:
			_script = level.decode_script(w["script"])
			_entry = -1
			_next_entry()
		1, 4, 5:
			pass
		_:
			_polar = level.decode_polar(w["script"])
			_pi = 0
			_ptimer = 0
	_update_hitbox(level)


static func _bcd(v: int) -> int:
	return ((v >> 12) & 15) * 1000 + ((v >> 8) & 15) * 100 + ((v >> 4) & 15) * 10 + (v & 15)


func _frame_record(level: LevelData, px: int) -> Dictionary:
	var idx := frame
	if frame == 0xFF or frame == 0xFE:
		var base := 0 if frame == 0xFF else 3
		var dxp := (px + 16) - int(x)
		if absi(dxp) < 0x28:
			idx = base
		elif dxp < 0:
			idx = base + 1
		else:
			idx = base + 2
	else:
		idx = frame + 6
	if idx < 0 or idx >= level.bob_frames.size():
		return {}
	return level.bob_frames[idx]


func _update_hitbox(level: LevelData, px: int = 0) -> void:
	var f := _frame_record(level, px)
	if not f.is_empty():
		hit_w = f["hit_w"]
		hit_h = f["hit_h"]


func _next_entry() -> void:
	_entry += 1
	if _entry >= _script.size():
		dead = true
		return
	_repeat = _script[_entry]["repeat"]
	_steps = _script[_entry]["steps"]
	_step = 0
	_timer = 0


func hit(dmg: int) -> void:
	hp -= dmg
	flash = 4
	if hp <= 0:
		dead = true


func want_fire(rng: RandomNumberGenerator) -> bool:
	if _fire_reload <= 0 or x < 0 or x > 300:
		return false
	_fire_t -= 1
	if _fire_t <= 0:
		_fire_t = _fire_reload
		return rng.randi() % 3 == 0
	return false


func tick(level: LevelData, px: int, py: int, scroll: float, _rng: RandomNumberGenerator) -> void:
	if dead:
		return
	if flash > 0:
		flash -= 1
	match type:
		2, 3:
			_tick_path(level)
		1, 4, 5:
			x = _world_x - scroll + 14.0
			if x < -48.0:
				dead = true
		_:
			_tick_polar(level)
	_update_hitbox(level, px)


func _tick_path(_level: LevelData) -> void:
	# consume steps until one with a duration is active
	var guard := 0
	while _timer <= 0 and guard < 64 and not dead:
		guard += 1
		if _step >= _steps.size():
			_repeat -= 1
			if _repeat > 0:
				_step = 0
			else:
				_next_entry()
				if dead:
					return
			continue
		var s: Dictionary = _steps[_step]
		_step += 1
		if s.has("frame"):
			frame = s["frame"]
		else:
			_timer = s["dur"]
			_dx = s["dx"]
			_dy = s["dy"]
	if _timer > 0:
		_timer -= 1
		x += _dx
		y += _dy
		if x < -32.0 or y < 0.0 or y > 250.0:
			dead = true


func _tick_polar(level: LevelData) -> void:
	var guard := 0
	while _ptimer <= 0 and guard < 32:
		guard += 1
		if _pi >= _polar.size():
			dead = true
			return
		var c: Dictionary = _polar[_pi]
		_pi += 1
		if c.has("code"):
			_code = c["code"]
		else:
			frame = c["frame"]
		_ptimer = c["dur"]
	_ptimer -= 1
	var d6 := _code & 0x3C
	var v0 := level.angle_entry(d6)
	var v1 := level.angle_entry(0x20 - d6)
	if (_code & 1) == 0:
		v0 = -v0
	if (_code & 2) == 0:
		v1 = -v1
	var mul := 4.0 if (_code & 0x40) else 2.0
	x += float(v0) / 65536.0 * mul
	y += float(v1) / 65536.0 * mul
	if x < 0.0 or y < 0.0 or x > 350.0 or y > 224.0:
		dead = true


func update_sprite(level: LevelData, field_y: int, x_off: int, tex_fn: Callable) -> void:
	var f := _frame_record(level, int(x) - 16)
	if f.is_empty() or not f.has("img"):
		spr.visible = false
		return
	spr.visible = true
	spr.texture = tex_fn.call(f["img"])
	spr.position = Vector2(x + f["xoff"] - x_off, y + f["yoff"] + field_y)
