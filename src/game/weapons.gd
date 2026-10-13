class_name Weapons
extends Node2D
## The player's shots, option pods and charge blast, ported from the original's shot handlers
## ($2758 and the routines it jumps to). Coordinates are the original's "raw" ones (see Game).
##
## Shot types (original handler numbers):
##   1 basic stinger   2..5 spread shots (weapon A)   6 missile (weapon B)   7 / 11 wave shots (weapon C)
##   8 pod shot   12 / 13 accelerating wave shots (weapon C level 3)
## A basic shot is consumed by whatever it hits; the others pierce when their damage is at least the
## target's remaining hit points.

signal sound(effect: int)
signal enemy_hit(enemy: Enemy, killed: bool)

const X_OFFSET := 14
const MAX_BASIC := 8
const STRAIGHT_A := 100
const STRAIGHT_B := 101

# y offsets of the wave tables ($887E small, $889E large), one period of 16 entries
const WAVE_SMALL := [-3, -3, -2, -1, 1, 2, 3, 3, 3, 3, 2, 1, -1, -2, -3, -3]
const WAVE_LARGE := [-8, -8, -6, -4, -1, 1, 4, 6, 8, 8, 6, 4, 1, -1, -4, -6]


class Shot extends RefCounted:
	var handler := 1
	var special := false      # drawn from the weapon tables, damage = dmg (basic shots always hit for 1)
	var dmg := 1
	var x := 0
	var y := 0
	var counter := 0          # lifetime of the spread shots
	var phase := 0            # byte index into the wave table
	var accel := 1
	var accel_t := 1
	var dead := false
	var sprites: Array[Sprite2D] = []


var level: LevelData
var state: PlayerState
var art_material: ShaderMaterial
var field_y := 8
var shots: Array[Shot] = []
var basic_count := 0
var special_count := 0
var pods_hp := 6
var charge := 45
var charge_ready_played := false
var blast_x := -1
var blast_y := 0
var blast_power := 0
var blast_frame := 0
var _blast_sprite: Sprite2D
var _anim_t1 := 2
var _anim_t2 := 2
var _frame_a := 0
var _frame_b := 0
var _pod_phase := 0
var _tex := {}
var _hist_x: Array[int] = []
var _hist_y: Array[int] = []
var _pod_sprites: Array[Sprite2D] = []
var pod_pos: Array[Vector2i] = [Vector2i(-100, 0), Vector2i(-100, 0)]


func setup(lv: LevelData, ps: PlayerState, mat: ShaderMaterial, fy: int) -> void:
	level = lv
	state = ps
	art_material = mat
	field_y = fy
	for i in 2:
		var s := Sprite2D.new()
		s.centered = false
		s.material = mat
		s.visible = false
		add_child(s)
		_pod_sprites.append(s)
	_blast_sprite = Sprite2D.new()
	_blast_sprite.centered = false
	_blast_sprite.material = mat
	_blast_sprite.visible = false
	add_child(_blast_sprite)
	for i in 32:
		_hist_x.append(0)
		_hist_y.append(0)


func _texture(img: Image) -> ImageTexture:
	var k := img.get_instance_id()
	if not _tex.has(k):
		_tex[k] = ImageTexture.create_from_image(img)
	return _tex[k]


func _sprite() -> Sprite2D:
	var s := Sprite2D.new()
	s.centered = false
	s.material = art_material
	add_child(s)
	return s


# ---- firing -------------------------------------------------------------------------------------
func _spawn(handler: int, x: int, y: int, special: bool, dmg: int, counter: int = 0, phase: int = 0) -> Shot:
	var s := Shot.new()
	s.handler = handler
	s.special = special
	s.dmg = dmg
	s.x = x
	s.y = y
	s.counter = counter
	s.phase = phase
	var parts := 3 if handler in [7, 11, 12, 13] else 1
	for i in parts:
		s.sprites.append(_sprite())
	shots.append(s)
	if special:
		special_count += 1
	else:
		basic_count += 1
	return s


## One press of the fire button ($1472..$1560). Returns true when a volley left.
func fire(px: int, py: int) -> bool:
	if basic_count >= MAX_BASIC:
		return false
	var x := px + 0x14
	var y := py + 0xF
	_spawn(1, x, y, false, 1)
	var sfx := 0
	# the extra shots only leave when no other special shot (pods count too) is still flying
	if special_count != 0:
		sound.emit(sfx)
		return true
	match state.weapon:
		1:
			sfx = _volley_spread(x, y)
		2:
			sfx = _volley_missiles(px, py)
		_:
			sfx = _volley_waves(px, py)
	# option pods fire straight stingers
	if state.pods != 0:
		_spawn(8, pod_pos[0].x + 5, pod_pos[0].y + 3, true, 2)
		if state.pods < 0:
			_spawn(8, pod_pos[1].x + 5, pod_pos[1].y + 3, true, 2)
	sound.emit(sfx)
	return true


func _volley_spread(x: int, y: int) -> int:
	var sfx := 0
	if state.w1 == 0:
		return sfx
	if state.w1 == 2:
		_spawn(3, x, y, true, 2, 10)
		_spawn(4, x, y, true, 2, 10)
		sfx += 1
	_spawn(2, x + 8, y, true, 2, 8)
	_spawn(5, x + 8, y, true, 2, 8)
	sfx += 1
	return sfx


func _volley_missiles(px: int, py: int) -> int:
	var x := px + 0x14
	match state.w2:
		1:
			_spawn(6, x, py + 0xF, true, 2)
		2:
			_spawn(6, x, py + 7, true, 2)
			_spawn(6, x, py + 0x17, true, 2)
		_:
			_spawn(6, x, py, true, 2)
			_spawn(6, x, py + 0x19, true, 2)
			_spawn(6, x + 6, py + 0xD, true, 2)
	return 3


func _volley_waves(px: int, py: int) -> int:
	var x := px + 0x14
	var y := py + 0xE
	var max_level := state.w3 >= 3
	var s1 := _spawn(12 if max_level else 7, x, y, true, 7 if max_level else 5)
	s1.accel = 1
	if state.w3 >= 1:
		var s2 := _spawn(13 if max_level else 11, x, y, true, 7 if max_level else 5, 0, 16)
		s2.accel = 1
	return 4


## Charge: holding fire counts down; releasing after the count reached zero lets the blast go.
func hold_fire(held: bool, px: int, py: int) -> void:
	if held:
		if charge > 0:
			charge -= 1
		elif not charge_ready_played:
			charge_ready_played = true
			sound.emit(5)
	else:
		if charge == 0 and blast_x < 0:
			blast_x = px + 0xA
			blast_y = py + 0xA
			blast_power = 0xF
			sound.emit(6)
		charge = 45
		charge_ready_played = false


# ---- per tick -----------------------------------------------------------------------------------
func tick(px: int, py: int, scroll: float, enemies: Array[Enemy], moved: bool) -> void:
	# animation counters of the shot tables (3 ticks per frame)
	_anim_t1 -= 1
	if _anim_t1 < 0:
		_anim_t1 = 2
		_frame_a = (_frame_a + 1) & 3
	_anim_t2 -= 1
	if _anim_t2 < 0:
		_anim_t2 = 2
		_frame_b = (_frame_b + 1) & 3
	_update_pods(px, py, moved)
	var keep: Array[Shot] = []
	for s in shots:
		_step(s)
		if not s.dead:
			_wall_test(s, scroll)
		if not s.dead:
			_enemy_test(s, enemies)
		if s.dead:
			for sp in s.sprites:
				sp.queue_free()
		else:
			keep.append(s)
	shots = keep
	_update_blast(enemies)


func _remove(s: Shot) -> void:
	if s.dead:
		return
	s.dead = true
	if s.special:
		special_count = maxi(0, special_count - 1)
	else:
		basic_count = maxi(0, basic_count - 1)


func _place(sp: Sprite2D, img: Image, x: int, y: int) -> void:
	sp.texture = _texture(img)
	sp.position = Vector2(x - X_OFFSET, y + field_y)
	sp.visible = true


func _step(s: Shot) -> void:
	var art := level.shot_art
	match s.handler:
		1:
			s.x += 12
			if s.x >= 0x14A:
				_remove(s)
				return
			_place(s.sprites[0], art["basic"], s.x, s.y)
		2, 3, 4, 5:
			s.counter -= 1
			if s.counter <= 0:
				s.handler = STRAIGHT_A if (s.handler == 2 or s.handler == 4) else STRAIGHT_B
				_step(s)
				return
			match s.handler:
				2: s.y += 2
				3: s.y += 4
				4: s.y -= 4
				5: s.y -= 2
			if s.y >= 0xEF or s.y < 0:
				_remove(s)
				return
			s.x += 0x10
			if s.x >= 0x14A:
				_remove(s)
				return
			_draw_spread(s, s.handler == 2 or s.handler == 4)
		STRAIGHT_A, STRAIGHT_B:
			s.x += 0x10
			if s.x >= 0x14A:
				_remove(s)
				return
			_draw_spread(s, s.handler == STRAIGHT_A)
		6:
			s.x += 0x10
			if s.x >= 0x14A:
				_remove(s)
				return
			var f: Dictionary = level.shot_art["w2"][_frame_b]["a"]
			_place(s.sprites[0], f["img"], s.x, s.y - 4 + f["yoff"])
		8:
			s.x += 12
			if s.x >= 0x14A:
				_remove(s)
				return
			_place(s.sprites[0], art["pod"], s.x, s.y)
		7, 11, 12, 13:
			_step_wave(s)


func _draw_spread(s: Shot, variant_a: bool) -> void:
	var f: Dictionary = level.shot_art["w1"][_frame_a]["a" if variant_a else "b"]
	_place(s.sprites[0], f["img"], s.x, s.y + f["yoff"])


func _step_wave(s: Shot) -> void:
	var big := s.handler == 12 or s.handler == 13
	var tab: Array = WAVE_LARGE if big else WAVE_SMALL
	var set_b := s.handler == 11 or s.handler == 13
	var set: Array = level.shot_art["wave_b" if set_b else "wave_a"]
	var idx := (s.phase & 0x1F) >> 1
	var prev: int = tab[(idx - 1) & 15]
	_place(s.sprites[0], set[0], s.x - 8, s.y - prev)
	_place(s.sprites[1], set[1], s.x - 1, s.y - 2)
	s.phase = (s.phase + 2) & 0x1F
	s.y += tab[idx]
	if s.y < 0:
		_remove(s)
		return
	var dx := 10
	if big:
		dx = s.accel
		s.accel_t -= 1
		if s.accel_t < 0:
			s.accel_t = 0
			if s.accel == 10:
				s.handler = 11 if set_b else 7
				# the plain wave handler takes over with its own table
			else:
				s.accel += 1
	s.x += dx
	if s.x >= 0x15E:
		_remove(s)
		return
	_place(s.sprites[2], set[2], s.x, s.y - 4)


func _wall_test(s: Shot, scroll: float) -> void:
	if level.cols == 0:
		return
	var wx := s.x - X_OFFSET + int(scroll)
	var col := wx >> 4
	var row := s.y >> 4
	if col < 0 or col >= level.cols or row < 0 or row >= LevelData.ROWS:
		return
	var w := level.map_words[row * level.cols + col] & 0x7800
	if w == 0:
		return
	var bit: int
	if s.x & 8:
		bit = 0x0800 if (s.y & 8) else 0x2000
	else:
		bit = 0x1000 if (s.y & 8) else 0x4000
	if w & bit:
		_remove(s)
		sound.emit(10)


func _enemy_test(s: Shot, enemies: Array[Enemy]) -> void:
	var sx := s.x + 0x14
	var sy := s.y - 4
	for e in enemies:
		if e.dead or e.hp <= 0 or e.invulnerable:
			continue
		var dx := sx - int(e.x)
		var dy := sy - int(e.y)
		if dx < -8 or dy < -8 or dx >= e.hit_w or dy >= e.hit_h:
			continue
		if not s.special:
			_remove(s)
			var killed := e.hit(1)
			enemy_hit.emit(e, killed)
			return
		var pre := e.hp
		if s.dmg >= pre:
			enemy_hit.emit(e, e.hit(pre))
			continue                       # strong shots keep flying
		_remove(s)
		enemy_hit.emit(e, e.hit(s.dmg))
		sound.emit(9)
		return


# ---- charge blast ($1F80 / $56E6) -------------------------------------------------------------------
func _update_blast(enemies: Array[Enemy]) -> void:
	if blast_x < 0:
		_blast_sprite.visible = false
		return
	for e in enemies:
		if e.dead or e.hp <= 0:
			continue
		if blast_x + 5 < e.x or blast_x > e.x + e.hit_w:
			continue
		if blast_y + 0x18 - 5 < e.y or blast_y - 5 > e.y + e.hit_h:
			continue
		var hp := e.hp
		if hp > blast_power:
			enemy_hit.emit(e, e.hit(blast_power))
			blast_x = -1
			_blast_sprite.visible = false
			return
		enemy_hit.emit(e, e.hit(hp))
		blast_power -= hp
		if blast_power <= 0:
			blast_x = -1
			_blast_sprite.visible = false
			return
	blast_x += 5
	if blast_x >= 0x13E:
		blast_x = -1
		_blast_sprite.visible = false
		return
	_place(_blast_sprite, level.shot_art["wave_b"][2], blast_x, blast_y)


# ---- pods ----------------------------------------------------------------------------------------------
func _update_pods(px: int, py: int, moved: bool) -> void:
	if moved or _hist_x[0] == 0:
		_hist_x.push_front(px - 0x12)
		_hist_y.push_front(py + 4)
		_hist_x.resize(32)
		_hist_y.resize(32)
	if state.pods == 0:
		for sp in _pod_sprites:
			sp.visible = false
		return
	var lag := 3
	var hx: int = _hist_x[lag]
	var hy: int = _hist_y[lag]
	match state.weapon:
		2:
			pod_pos[0] = Vector2i(hx + 0x1C, hy - 0xA)
			pod_pos[1] = Vector2i(hx + 0x1C, hy + 0x1E)
		1:
			pod_pos[0] = Vector2i(_hist_x[15] + 0x1A, _hist_y[15] + 0xA)
			pod_pos[1] = Vector2i(_hist_x[30] + 0x1A, _hist_y[30] + 0xA)
		_:
			pod_pos[0] = Vector2i(hx + 0x37, hy + 0xA)
			pod_pos[1] = Vector2i(hx - 2, hy + 0xA)
	_pod_phase = (_pod_phase + 1) & 15
	var f: Dictionary = level.shot_art["pods"][_pod_phase >> 2]
	for i in 2:
		var sp := _pod_sprites[i]
		sp.visible = i == 0 or state.pods < 0
		if sp.visible:
			_place(sp, f["img"], pod_pos[i].x, pod_pos[i].y + f["yoff"])


func clear() -> void:
	for s in shots:
		for sp in s.sprites:
			sp.queue_free()
	shots.clear()
	basic_count = 0
	special_count = 0
	blast_x = -1
