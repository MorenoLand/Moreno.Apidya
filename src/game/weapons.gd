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
signal explosion(x: float, y: float)

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

# bombs: variant 1 is lobbed ($3522), variant -1 are two crawlers that follow the terrain ($3758)
const BOMB_FLIGHT := [[2, 1, 5], [4, 2, 4], [4, 3, 2], [3, 4, 1], [1, 0, 0]]   # ticks, dx, dy; the last first
const CRAWL_DY := [-4, -2, 0, 2, 4]
var bomb_x := -1                 # $7C6E, -1: not in flight
var bomb_y := 0
var _bomb_phase := 0
var _bomb_t := 0
var _bomb_dx := 0
var _bomb_dy := 0
var _bomb_latch := false         # $7C14: one bomb per press of the fire button
var _bomb_anim := 5              # $7C7A
var _bomb_anim_t := 0            # $7C7F
var _bomb_spr: Sprite2D
var _crawl_x: Array[int] = [-1, -1]
var _crawl_y: Array[int] = [0, 0]
var _crawl_s: Array[int] = [0, 4]
var _crawl_spr: Array[Sprite2D] = []


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
	_bomb_spr = Sprite2D.new()
	_bomb_spr.centered = false
	_bomb_spr.material = mat
	_bomb_spr.visible = false
	add_child(_bomb_spr)
	for i in 2:
		var c := Sprite2D.new()
		c.centered = false
		c.material = mat
		c.visible = false
		add_child(c)
		_crawl_spr.append(c)


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
		_try_bomb(px, py)
		if charge > 0:
			charge -= 1
		elif not charge_ready_played:
			charge_ready_played = true
			sound.emit(5)
	else:
		_bomb_latch = false
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
	_update_bombs(scroll, enemies)


## A shot used up by the original's own code (a handler tested it against its parts).
## All shots, the bomb and the blast are gone (the level restarts).
func clear_shots() -> void:
	for s in shots:
		for sp in s.sprites:
			sp.queue_free()
	shots.clear()
	basic_count = 0
	special_count = 0
	bomb_x = -1
	_bomb_spr.visible = false
	_crawl_x = [-1, -1]
	for c in _crawl_spr:
		c.visible = false
	blast_x = -1
	_blast_sprite.visible = false


func consume(s: Shot) -> void:
	_remove(s)


func consume_blast() -> void:
	blast_x = -1
	_blast_sprite.visible = false


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
	# the original tests the tile of the column counter plus raw x / 16 (no scroll phase): the picture's
	# phase is not part of it, so the test point is ahead of the drawn tip by the phase
	var wx := s.x + int(scroll) - (int(scroll) & 15)
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


# ---- collision tests of handlers that check the player's shots themselves --------------------------------
## `$5BC8`: the first shot inside the box (record coordinates) is used up; returns its damage (0: none).
func test_shots_box(x0: int, y0: int, x1: int, y1: int) -> int:
	for s in shots:
		if s.dead:
			continue
		if s.x < x0 or s.x > x1 or s.y < y0 or s.y > y1:
			continue
		var dmg := s.dmg if s.special else 1
		_remove(s)
		return dmg
	return 0


## `$5C78`: the charge blast inside the box is used up and does 15.
func test_blast_box(x0: int, y0: int, x1: int, y1: int) -> int:
	if blast_x < 0:
		return 0
	if blast_x + 5 < x0 or blast_x > x1:
		return 0
	var top := blast_y - 5
	if top + 0x18 < y0 or top > y1:
		return 0
	blast_x = -1
	_blast_sprite.visible = false
	return 15


# ---- bombs --------------------------------------------------------------------------------------------
## A press of the fire button throws a bomb when none is in flight ($13EE..$1466).
func _try_bomb(px: int, py: int) -> void:
	if _bomb_latch or state.bomb == 0:
		return
	if bomb_x >= 0 or _crawl_x[0] >= 0 or _crawl_x[1] >= 0:
		return
	if state.bomb > 0:
		bomb_x = px
		bomb_y = py + 0xF
		_bomb_phase = 4
		_bomb_t = 1
		_bomb_dx = 0
		_bomb_dy = 0
	else:
		_crawl_x = [px - 8, px - 8]
		_crawl_y = [py + 0xA, py + 0xA + 0xC]
		_crawl_s = [0, 4]
	_bomb_latch = true


func _bomb_image(frame: int, colour_base: int) -> Image:
	var key := "bomb%d_%d" % [frame, colour_base]
	if _tex.has(key):
		return _tex[key]
	var f: Dictionary = level.bomb_frames[frame]
	var img := Image.create(16, f["h"], false, Image.FORMAT_LA8)
	var px: PackedByteArray = f["px"]
	for y in int(f["h"]):
		for x in 16:
			var v: int = px[y * 16 + x]
			img.set_pixel(x, y, Color8(colour_base + v, colour_base + v, colour_base + v, 255 if v != 0 else 0))
	_tex[key] = img
	return img


func _tile(col: int, row: int) -> int:
	if level.cols == 0 or col < 0 or col >= level.cols or row < 0 or row >= LevelData.ROWS:
		return 0
	return level.map_words[row * level.cols + col]


func _signed8(v: int) -> int:
	return v - 256 if v >= 128 else v


## Damage a bomb does to the first enemy in its box: 2, and it is used up. Returns true when it hit.
func _bomb_hits(enemies: Array[Enemy], left: int, top: int, right: int, bottom: int, ex: int, ey: int) -> bool:
	for e in enemies:
		if e.dead:
			continue
		if right < int(e.x) or bottom < int(e.y):
			continue
		if left > int(e.x) + _signed8(e.hit_w) or top > int(e.y) + _signed8(e.hit_h):
			continue
		if e.hp <= 0:
			return true                            # nothing left to damage: the bomb vanishes
		if e.hp <= 2:
			enemy_hit.emit(e, e.hit(e.hp))
			return true                            # kills it, no blast of its own
		enemy_hit.emit(e, e.hit(2))
		explosion.emit(float(ex), float(ey))
		sound.emit(11)
		return true
	return false


func _update_bombs(scroll: float, enemies: Array[Enemy]) -> void:
	if level.bomb_frames.is_empty():
		return
	_bomb_anim_t -= 1
	if _bomb_anim_t < 0:
		_bomb_anim_t = 1
		_bomb_anim -= 1
		if _bomb_anim < 0:
			_bomb_anim = 5
	var fr: Dictionary = level.bomb_frames[_bomb_anim]
	# lobbed bomb
	if bomb_x >= 0:
		_bomb_t = (_bomb_t - 1) & 0xFF
		if _bomb_t == 0 and _bomb_phase >= 0:
			var st: Array = BOMB_FLIGHT[_bomb_phase]
			_bomb_t = st[0]
			_bomb_dx = st[1]
			_bomb_dy = st[2]
			_bomb_phase -= 1
		bomb_x += _bomb_dx
		bomb_y += _bomb_dy
		var gone := bomb_y >= 0xF0
		if not gone:
			gone = _bomb_hits(enemies, bomb_x + 0x10, bomb_y, bomb_x + 0x10 + 0x14, bomb_y + 0x10, bomb_x + 0x10, bomb_y)
		if not gone and _solid_at(bomb_x, bomb_y + 0xA, scroll):
			explosion.emit(float(bomb_x + 0x10), float(bomb_y))
			sound.emit(11)
			gone = true
		if gone:
			bomb_x = -1
	if bomb_x >= 0:
		_place(_bomb_spr, _bomb_image(_bomb_anim, 16), bomb_x + X_OFFSET, bomb_y + 4 + int(fr["yoff"]))
	else:
		_bomb_spr.visible = false
	# crawlers
	for i in 2:
		if _crawl_x[i] < 0:
			continue
		_crawl_x[i] += 4
		if _crawl_x[i] > 0x14E:
			_crawl_x[i] = -1
			continue
		_crawl_y[i] += CRAWL_DY[_crawl_s[i]]
		if _crawl_y[i] < 0 or _crawl_y[i] >= 0xF0:
			_crawl_x[i] = -1
			continue
		_crawl_turn(i, scroll)
		var cx := _crawl_x[i]
		var cy := _crawl_y[i]
		if _bomb_hits(enemies, cx, cy, cx + 0x10, cy + 0x10, cx + 0x10, cy):
			_crawl_x[i] = -1
			continue
		_place(_crawl_spr[i], _bomb_image(_bomb_anim, 20), cx + X_OFFSET, cy + 4 + int(fr["yoff"]))
	for i in 2:
		if _crawl_x[i] < 0:
			_crawl_spr[i].visible = false


## Does the 8x8 quadrant of the playfield under the raw point (x, y) have its collision bit set?
func _solid_at(x: int, y: int, scroll: float) -> bool:
	return solid_world(x + int(scroll) - (int(scroll) & 15), y)


## Is the 8x8 quadrant of the map under the world point (wx, y) marked solid? `y` is the raw row
## ($7800 collision bits of the tile word, quadrant chosen by bit 3 of x and y).
func solid_world(wx: int, y: int) -> bool:
	var w := _tile(wx >> 4, y >> 4) & 0x7800
	if w == 0:
		return false
	var bit: int
	if wx & 8:
		bit = 0x0800 if (y & 8) else 0x2000
	else:
		bit = 0x1000 if (y & 8) else 0x4000
	return (w & bit) != 0


## The state of a crawler (0..4 = vertical speed -4..4) follows the walls around it ($3812..$3916).
func _crawl_turn(i: int, scroll: float) -> void:
	var col := (_crawl_x[i] + int(scroll) - (int(scroll) & 15)) >> 4
	var row := _crawl_y[i] >> 4
	var mask := 0x1800 if (_crawl_y[i] & 8) else 0x6000
	var s: int = _crawl_s[i]
	var up_l := (_tile(col, row - 1) & mask) != 0
	var up_m := (_tile(col + 1, row - 1) & mask) != 0
	var mid_m := (_tile(col + 1, row) & mask) != 0
	var mid_r := (_tile(col + 2, row) & mask) != 0
	var dn_l := (_tile(col, row + 1) & mask) != 0
	var dn_m := (_tile(col + 1, row + 1) & mask) != 0
	var dn_r := (_tile(col + 2, row + 1) & mask) != 0
	if i == 0:
		match s:
			0:
				if up_l:
					s += 1
			1:
				if not up_l:
					s -= 1
				elif up_m:
					s += 1
			2:
				if not up_m:
					s -= 1
				elif mid_r:
					s += 1
			3:
				if mid_m:
					s += 1
				elif not mid_r:
					s -= 1
			_:
				if not mid_m:
					s -= 1
	else:
		match s:
			0:
				if not dn_m:
					s += 1
			1:
				if not dn_m:
					s += 1
				elif mid_r:
					s -= 1
			2:
				if not dn_m:
					s += 1
				elif mid_m:
					s -= 1
			3:
				if dn_r:
					s -= 1
				elif not dn_m:
					s += 1
			_:
				if dn_l:
					s -= 1
	_crawl_s[i] = clampi(s, 0, 4)


## `$5C1E`: the bomb inside the box of a boss part is used up (explodes) and does 2.
func test_bomb_box(x0: int, y0: int, x1: int, y1: int) -> int:
	if bomb_x < 0:
		return 0
	if bomb_x + 0x10 > x1 or bomb_x + 0x24 < x0 or bomb_y > y1 or bomb_y + 0x10 < y0:
		return 0
	explosion.emit(float(bomb_x + 0x10), float(bomb_y))
	sound.emit(11)
	bomb_x = -1
	return 2


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
