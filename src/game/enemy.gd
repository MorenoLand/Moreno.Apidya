class_name Enemy
extends RefCounted
## One enemy. Behaviour follows the original's updater: type 1 scroll-locked objects, 2/3 path
## followers, 4/5 "native handler" objects (guardians, shooters, set pieces; see Handlers*), 6+ polar
## movers. `rec` mirrors bytes 0x0C..0x1F of the original 32-byte record so that the handlers can
## be ported one to one.

var spr: Sprite2D
var parts: Array[Sprite2D] = []    # extra sprites a handler draws (boss pieces)
var type := 1
var x := 0.0                 # raw coordinates
var y := 0.0
var hp := 1
var score := 0
var frame := 0
var hit_w := 16
var hit_h := 16
var dead := false
var killed := false          # destroyed by the player (as opposed to leaving the screen)
var flash := 0
var invulnerable := false
var group := -1              # formation group slot this enemy counts for
var flags := 0               # type word >> 9: 8 = animation phase B, 0x10 = hidden, 0x20 = large frame list
var no_draw := false         # handler asks for no standard sprite this tick
var phase := 0               # extra frame offset (the original's D6)
var level: LevelData
var handler_addr := 0
var handler := Callable()
var rec := PackedByteArray() # original record bytes, indexed by original offset (0..0x25)
var hp_bits := 0             # bits of the hit point byte that are neither hit points nor the flash flag (levels 4, 5)
var set_piece := false       # type 5: opaque image blitted into the playfield
var pix_x := 0               # type 5 position in the playfield (pixels, world x without scroll)
var pix_y := 0
var world_x := 0.0           # type 1 / 5: x in the scrolled playfield
var spawn_scroll := 0.0
var vx := 0.0                # free velocity for projectile-like enemies
var vy := 0.0
var v := {}                  # free per-instance state of a handler
var dying := false           # hit points ran out; a death sequence / the handler finishes it
var owns_death := false      # the handler runs the death sequence itself
var on_death := Callable()   # called when the enemy was destroyed: func(g: Game, e: Enemy)
var fixed_hitbox := false
var vm_slot := -1            # >= 0: the original handler code runs this enemy (HandlerVM)
var vm_draws: Array = []     # sprites the handler asked for this tick
var vm_blits: Array = []     # blitter copies the handler did this tick
var vm_freed := false
var flash_bit := false       # bit 7 of the hit point byte
var _death_ptr := 0
var _death_t := 1

static var phase_a := 0      # shared animation phases (the original's $7CAC / $7CAD)
static var phase_b := 0

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


## Record as the spawner leaves it: levels 4 and 5 keep six more bytes (a second playfield offset
## word and two position words) behind the 32 common ones.
func _init_record(const10: int) -> void:
	rec.resize(0x26)
	rec[0x20] = 0xFF
	rec[0x21] = 0xFF
	rec[0x22] = 0x80
	rec[0x24] = 0x80
	set_rw(0x10, const10)


func init_from_wave(w: Dictionary, lv: LevelData, scroll: float, group_slot: int = -1) -> void:
	level = lv
	type = w["type"]
	flags = w.get("flags", 0)
	group = group_slot
	x = float(w["x"])
	y = float(w["y"])
	hp = maxi(1, w["hp"])
	frame = w["frame"]
	score = _bcd(w["score_bcd"])
	world_x = x - 14.0 + scroll
	spawn_scroll = scroll
	_init_record(lv.rec_const10)
	rec[0x0C] = w["fire_timer"]
	rec[0x0D] = w["fire_reload"]
	set_rw(0x0E, w["script"])
	set_rw(0x12, 0x101)
	set_rw(0x14, w["p6"])
	set_rw(0x16, w["p7"])
	set_rw(0x18, 0x100)
	set_rw(0x1A, w["score_bcd"])
	set_rw(0x1C, w["handler"])
	set_rw(0x1E, w["p11"])
	handler_addr = w["handler"]
	_off0 = w["p11"]
	match type:
		2, 3:
			set_path_script(w["script"])
		1:
			pass
		4, 5:
			set_piece = type == 5
			if set_piece:
				# the playfield offset of the object: 230 bytes per line (5 planes of 46)
				var off: int = w["p11"]
				pix_x = (off % 230) * 8
				pix_y = off / 230
		_:
			_polar = lv.decode_polar(w["script"])
			_pi = 0
			_ptimer = 0
	_update_hitbox()


static func _bcd(v: int) -> int:
	return ((v >> 12) & 15) * 1000 + ((v >> 8) & 15) * 100 + ((v >> 4) & 15) * 10 + (v & 15)


# ---- record helpers ----------------------------------------------------------------------------
func rb(o: int) -> int:
	return rec[o]


func set_rb(o: int, v: int) -> void:
	rec[o] = v & 0xFF


func rw(o: int) -> int:
	return (rec[o] << 8) | rec[o + 1]


func set_rw(o: int, v: int) -> void:
	rec[o] = (v >> 8) & 0xFF
	rec[o + 1] = v & 0xFF


func rsw(o: int) -> int:
	var v := rw(o)
	return v - 65536 if v >= 32768 else v


func rl(o: int) -> int:
	return (rw(o) << 16) | rw(o + 2)


func set_rl(o: int, v: int) -> void:
	set_rw(o, (v >> 16) & 0xFFFF)
	set_rw(o + 2, v & 0xFFFF)


## Replaces the movement script (the original sets +E / +10 / +12 for this).
func set_path_script(ptr: int) -> void:
	_script = level.decode_script(ptr)
	_entry = -1
	_next_entry()


# ---- animation frame ---------------------------------------------------------------------------
func _frame_record(px: int) -> Dictionary:
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
		var base := 51 if (flags & 0x20) else 6
		var ph := phase
		if type == 3 or type >= 7:
			ph += phase_b if (flags & 8) else phase_a
		idx = frame + base + ph
	if idx < 0 or idx >= level.bob_frames.size():
		return {}
	return level.bob_frames[idx]


func set_hitbox(w: int, h: int) -> void:
	hit_w = w
	hit_h = h
	fixed_hitbox = true


func _update_hitbox(px: int = 0) -> void:
	if type == 5 or fixed_hitbox:
		return
	var f := _frame_record(px)
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


## Applies damage; returns true when this destroyed the enemy.
func hit(dmg: int) -> bool:
	if dying or dead:
		return false
	if vm_slot >= 0:
		# the handler's own code decides about death (it looks at the byte at +8 each tick)
		hp = maxi(0, hp - dmg)
		flash_bit = true
		return false
	hp -= dmg
	flash = 4
	if hp <= 0:
		hp = 0
		if owns_death:
			dying = true
			return true
		if rw(0x16) != 0:
			_begin_death_pattern()
			return true
		dead = true
		killed = true
		return true
	return false


## Enemies with a pattern pointer in +0x16 do not vanish at once: they explode piece by piece
## (the original's $3220 pattern: 1 dx dy = blast, 2 n = wait, other = body disappears, bit 7 = end).
func _begin_death_pattern() -> void:
	dying = true
	_death_ptr = rw(0x16)
	_death_t = 1
	group = -1


func _death_step(g: Game) -> void:
	_death_t -= 1
	var guard := 0
	while _death_t <= 0 and guard < 32:
		guard += 1
		var op := level.read_u8(_death_ptr)
		if op >= 128:
			dead = true
			killed = true
			on_death = Callable()
			return
		if op == 1:
			var dx := _s8(level.read_u8(_death_ptr + 1))
			var dy := _s8(level.read_u8(_death_ptr + 2))
			_death_ptr += 3
			g.explode(x + dx, y + dy)
			g.sfx(0x0C)
			_death_t = 1
		elif op == 2:
			_death_t = level.read_u8(_death_ptr + 1)
			_death_ptr += 2
		else:
			_death_ptr += 1
			flags |= 0x10
			_death_t = 1


# ---- per tick ----------------------------------------------------------------------------------
func tick(g: Game) -> void:
	if dead:
		return
	if flash > 0:
		flash -= 1
	no_draw = false
	if dying and not owns_death:
		_death_step(g)
		return
	match type:
		2, 3:
			follow_path()
			_fire_std(g)
		1:
			x = world_x - g.scroll + 14.0
			if x < -48.0:
				dead = true
			_fire_std(g)
		4, 5:
			if handler.is_valid():
				handler.call(g, self)
			else:
				x = world_x - g.scroll + 14.0
				if x < -48.0:
					dead = true
		_:
			_tick_polar()
			_fire_std(g)
	_update_hitbox(g.px)


## The standard fire code of the draw tails: a random half of the ticks counts the timer down; at
## zero the shot goes out aimed at the player and the timer reloads.
func _fire_std(g: Game) -> void:
	if dead or x < 0 or x > 330:
		return
	if g.rng.randi() & 1:
		rec[0x0C] = (rec[0x0C] - 1) & 0xFF
		if rec[0x0C] == 0:
			rec[0x0C] = rec[0x0D]
			g.fire_aimed(x + _s8(rec[0x14]), y + _s8(rec[0x15]))


static func _s8(v: int) -> int:
	return v - 256 if v >= 128 else v


## Path follower step (the original's $3E30). Frees the enemy when the script ends or it leaves.
func follow_path() -> void:
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


func _tick_polar() -> void:
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


# ---- drawing -------------------------------------------------------------------------------------
var _off0 := 0

## Screen position (px) of a type 5 set piece: its playfield offset, as the handlers move it by
## changing +0x1E (one text line = 230 bytes, 8 pixels per byte).
func set_piece_pos(g: Game) -> Vector2:
	var delta := ((rw(0x1E) - _off0 + 32768) & 0xFFFF) - 32768
	var lines := roundi(delta / 230.0)
	var xb := delta - lines * 230
	return Vector2(pix_x + xb * 8 + spawn_scroll - g.scroll, pix_y + lines)


func update_sprite(g: Game, field_y: int, x_off: int, tex_fn: Callable) -> void:
	if set_piece:
		if no_draw or (flags & 0x10) or frame >= level.set_pieces.size():
			spr.visible = false
			return
		var pp: Dictionary = level.set_pieces[frame]
		spr.visible = true
		spr.texture = tex_fn.call(pp["alt"] if flash > 0 else pp["img"])
		var pos := set_piece_pos(g)
		spr.position = Vector2(pos.x, pos.y + field_y)
		return
	if no_draw or (flags & 0x10):
		spr.visible = false
		return
	var f := _frame_record(int(x) - 16)
	if f.is_empty() or not f.has("img"):
		spr.visible = false
		return
	spr.visible = true
	spr.texture = tex_fn.call(f["img"])
	spr.position = Vector2(x + f["xoff"] - x_off, y + f["yoff"] + field_y)
