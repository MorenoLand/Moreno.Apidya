class_name HandlersL1
extends RefCounted
## Level 1 ("Garden") native handlers. Addresses are those of the original level file; the comments
## give the routine each one is ported from. Global variables that the original keeps inside its code
## ($48F6 ...) are static variables here, so that several instances share them just like there.

static var _ball_t := 0           # $461A / $461C: animation of the thrown ball
static var _ball_i := 0
static var _plant_t := 0          # $48F6 group: ground cannon timer state
static var _cannon_t := 0         # $4B36
static var _spitter_t := 0x1000   # $4B36 (guardian shooters)
static var _vine_phase := 0       # $492C / $492D
static var _vine_t := 0
static var _mini_state := 0       # $4BCA..$4D00 mini guardian
static var _boss_t := {}

const BALL_GFX := [0x28884, 0x28A64, 0x289C4, 0x28924]
const BALL_MASK := 0x293EC


static func get_handler(addr: int) -> Callable:
	match addr:
		0x4558: return Callable(HandlersL1, "h4558")
		0x4582: return Callable(HandlersL1, "h4582")
		0x45E2: return Callable(HandlersL1, "h45e2")
		0x4632: return Callable(HandlersL1, "h4632")
		0x4794: return Callable(HandlersL1, "h4794")
		0x4862: return Callable(HandlersL1, "h4862")
		0x492E: return Callable(HandlersL1, "h492e")
		0x4AB0: return Callable(HandlersL1, "h4ab0")
		0x4B38: return Callable(HandlersL1, "h4b38")
		0x4BCE: return Callable(HandlersL1, "h4bce")
		0x4D02: return Callable(HandlersL1, "h4d02")
		0x4D26: return Callable(HandlersL1, "h4d26")
		0x4548: return Callable(HandlersL1, "h4548")
		0x4FF6: return Callable(HandlersL1, "h4ff6")
	return Callable()


# ---- $4558 / $4582: fliers that spit three shots sideways -------------------------------------------
static func h4558(g: Game, e: Enemy) -> void:
	e.set_rb(0x14, e.rb(0x14) - 1)
	if e.rb(0x14) == 0:
		e.set_path_script(0x6CAE)
		e.set_rb(0x0D, 1)
		e.handler = Callable(HandlersL1, "h45e2")
	h4582(g, e)


static func h4582(g: Game, e: Enemy) -> void:
	e.set_rb(0x0C, 0x7F)
	e.set_rb(0x19, e.rb(0x19) - 1)
	if not Handlers.bpl(e.rb(0x19)):
		var x := e.x
		var y := e.y + 10.0
		var d5 := 0x80000
		if e.rb(0x0D) == 0:
			x += 0x20
		else:
			d5 = -0x80000
		g.fire_vel(x, y, d5, -0x8000)
		g.fire_vel(x, y, d5, 0)
		g.fire_vel(x, y, d5, 0x8000)
		g.sfx(7)
		e.set_rb(0x19, 0x64)
	h45e2(g, e)


static func h45e2(g: Game, e: Enemy) -> void:
	e.flash = 0
	Handlers.tail_path(g, e)


# ---- $4632: carries a ball, stops and throws it ($4712 is the ball) -------------------------------------
static func _ball_anim() -> void:
	_ball_t -= 1
	if _ball_t < 0:
		_ball_t = 6
		_ball_i = (_ball_i - 1) & 3


static func h4632(g: Game, e: Enemy) -> void:
	var st := e.rb(0x19)
	if st == 0:
		_ball_anim()
		var bx := e.x - 0x10
		if bx >= -0x10:
			g.draw_part(e, 0, g.level_plane_image(BALL_GFX[_ball_i], BALL_MASK, 1, 16), bx, e.y - 3)
		e.vx = 12.0
		e.set_rw(0x1E, e.rw(0x1E) - 1)
		if e.rw(0x1E) == 0:
			e.set_rb(0x19, 1)
		Handlers.tail_path(g, e)
		return
	if st >= 128:
		Handlers.tail_path(g, e)
		return
	# state 1 / 2: stands still, throws the ball once its countdown ran out
	e.x -= 1
	e.frame = 0x13
	e.vx -= 1.0
	if e.vx < 0.0:
		e.set_rb(0x19, 0xFF)
	elif st != 2:
		g.sfx(0x13)
		var b := g.spawn_native(e.x - 0x10, e.y - 3, 0x7F, 0, Callable(HandlersL1, "h4712"), 0x10, 0x10)
		b.vy = 7.0
		e.set_rb(0x19, 2)
	Handlers.tail_draw(e)


## $4712: the bouncing ball
static func h4712(g: Game, e: Enemy) -> void:
	e.y -= e.vy
	e.vy -= 0.125
	if e.y >= 0xD2:
		e.y = 0xD1
		e.vy = 4.0
		g.sfx(0x0A)
	e.x -= 1
	e.x -= g.scroll_step()
	if e.x < 0:
		e.dead = true
		return
	_ball_anim()
	e.no_draw = true
	g.draw_part(e, 0, g.level_plane_image(BALL_GFX[_ball_i], BALL_MASK, 1, 16), e.x, e.y)


# ---- $4794: ground plant that pops up and spits a big shot ---------------------------------------------
static func h4794(g: Game, e: Enemy) -> void:
	e.set_rb(0x0C, 0x7F)
	e.x -= g.scroll_step()
	e.set_rb(0x0F, e.rb(0x0F) - 1)
	if not Handlers.bpl(e.rb(0x0F)):
		e.set_rb(0x0F, 5)
		var st := e.rb(0x0E)
		if st == 0:
			e.hp = maxi(1, e.rb(0x14))
			e.set_rb(0x19, e.rb(0x19) - 1)
			if Handlers.bpl(e.rb(0x19)):
				e.no_draw = true
				return
			e.set_rb(0x0E, 1)
		elif st >= 128:
			if e.frame != 0x0D:
				e.frame -= 1
			elif (e.flags & 0x10) == 0:
				e.flags |= 0x10
			else:
				e.set_rb(0x19, 10)
				e.set_rb(0x0E, 0)
				e.set_rb(0x14, e.hp & 0x7F)
		else:
			if e.frame == 0x0F:
				e.set_rb(0x0E, 0xFF)
				g.fire_dir(e.x - 8, e.y, 3)
				g.sfx(7)
			elif (e.flags & 0x10) != 0:
				e.flags &= ~0x10
			else:
				e.frame += 1
	if (e.flags & 0x10) != 0:
		e.no_draw = true
		return
	Handlers.tail_draw(e)


# ---- $4862: ground cannon (set piece, frames 6..8) ---------------------------------------------------
static func h4862(g: Game, e: Enemy) -> void:
	e.set_rw(0x0A, 0x2010)
	e.hit_w = 0x20
	e.hit_h = 0x10
	e.flash = 0
	if _plant_state == 0:
		_plant_cnt -= g.rng.randi() & 0x3F
		if _plant_cnt < 0:
			_plant_cnt = 0x800
			_plant_state = 1
	else:
		_plant_sub -= 1
		if _plant_sub < 0:
			_plant_sub = 5
			if _plant_state < 0:
				if e.frame == 6:
					_plant_state = 0
				else:
					e.frame -= 1
			elif e.frame == 8:
				_plant_state = -1
				_plant_sub = 0xF
				g.spawn_heavy(e.x, e.y)
				g.sfx(8)
			else:
				e.frame += 1
	Handlers.tail_path(g, e, true)


static var _plant_state := 0
static var _plant_cnt := 0x0C00
static var _plant_sub := 5


# ---- $492E: vertical sweeper that bursts into six shots when destroyed -------------------------------------
static func h492e(g: Game, e: Enemy) -> void:
	e.flash = 0
	if e.hp <= 0:
		return
	e.set_rw(0x0A, 0x141E)
	e.hit_w = 0x14
	e.hit_h = 0x1E
	_vine_t -= 1
	if _vine_t < 0:
		_vine_t = 10
		_vine_phase ^= 1
	e.frame = 0x10 + _vine_phase
	e.x -= g.scroll_step()
	var up := e.rb(0x19) != 0
	if up:
		e.y -= 1
		e.set_rw(0x1E, e.rw(0x1E) - 0xE6)
		if e.y <= 0x32:
			e.set_rb(0x19, e.rb(0x19) ^ 1)
	else:
		e.y += 1
		e.set_rw(0x1E, e.rw(0x1E) + 0xE6)
		if e.y >= 0x8C:
			e.set_rb(0x19, e.rb(0x19) ^ 1)


# ---- $4AB0: hovering shooter with boomerang shots and a ball dropper ---------------------------------------
static func h4ab0(g: Game, e: Enemy) -> void:
	e.set_rw(0x0C, 0x7F7F)
	e.set_rb(0x19, e.rb(0x19) - 1)
	if not Handlers.bpl(e.rb(0x19)):
		e.set_rb(0x19, 0x50)
		g.fire_boomerang(e.x, e.y + 0xF, 1)
		g.fire_boomerang(e.x, e.y + 0xF, 0)
	_spitter_t -= g.rng.randi() & 0x3F
	if _spitter_t < 0:
		_spitter_t = 0x1000
		g.spawn_ball(e.x, e.y + 0x14)
		g.sfx(8)
	Handlers.tail_path(g, e)


# ---- $4B38: cannon set piece that lobs balls -------------------------------------------------------------
static func h4b38(g: Game, e: Enemy) -> void:
	e.flash = 0
	e.x -= g.scroll_step()
	if _cannon_state == 0:
		_cannon_t -= g.rng.randi() & 0x3F
		if _cannon_t < 0:
			_cannon_t = 0x1000
			_cannon_state = 1
		return
	_cannon_sub -= 1
	if _cannon_sub >= 0:
		return
	_cannon_sub = 8
	if _cannon_state > 0:
		if e.frame == 2:
			g.spawn_ball(e.x, e.y)
			g.sfx(8)
			_cannon_state = -1
		else:
			e.frame += 1
	else:
		if e.frame == 0:
			_cannon_state = 0
		else:
			e.frame -= 1


static var _cannon_state := 0
static var _cannon_sub := 0


## $4548: invisible mover that only carries a hit box
static func h4548(g: Game, e: Enemy) -> void:
	e.flash = 0
	Handlers.tail_path(g, e, true)


# ---- $4BCE: first guardian, $4D02 its claw ----------------------------------------------------------------
static func h4bce(g: Game, e: Enemy) -> void:
	if not _boss_t.has("init"):
		_boss_t = {"init": true, "a": 0, "b": 0, "life": 0x4A8, "timer1": 0x1000, "timer2": 0x1000,
			"spiral": 0x2001, "state": 1, "wait": 0xC0, "claw": 0x32}
	var b := _boss_t
	if b["state"] > 0 and b["wait"] > 0:
		b["wait"] -= 1
		e.x -= g.scroll_step()
		if b["wait"] == 0:
			b["state"] = 0
			g.scroll_locked = true
	elif b["state"] == 0:
		g.scroll_locked = true
	e.flash = 0
	e.set_rw(0x0A, 0x102D)
	e.hit_w = 0x10
	e.hit_h = 0x2D
	b["life"] -= 1
	if b["life"] <= 0:
		_mini_leave(g, e)
		return
	b["timer1"] -= g.rng.randi() & 0x3F
	if b["timer1"] < 0:
		b["timer1"] = 0x0A00
		e.frame = 0x0A
		g.spawn_heavy(e.x, e.y)
		g.sfx(8)
		b["a"] = 0x1E
	if b["a"] > 0:
		b["a"] -= 1
		if b["a"] == 0:
			e.frame = 9
	b["timer2"] -= g.rng.randi() & 0x3F
	if b["timer2"] < 0:
		b["timer2"] = 0x100
		b["spiral"] = (b["spiral"] + 0x200) & 0x1FFF
		g.fire_dir(e.x, e.y, b["spiral"])
		g.sfx(7)
	Handlers.tail_draw(e)


static func _mini_leave(g: Game, e: Enemy) -> void:
	g.scroll_locked = false
	g.phase_event = 1
	e.dead = true


static func h4d02(g: Game, e: Enemy) -> void:
	e.flash = 0
	if _boss_t.has("init") and _boss_t.get("state", 1) < 0:
		e.dead = true
		return
	_boss_t["claw"] = _boss_t.get("claw", 0x32) - 1
	if _boss_t["claw"] < 0:
		_boss_t["claw"] = 0x32
		e.frame ^= 7
	Handlers.tail_draw(e)


# ---- $4D26: the level guardian ----------------------------------------------------------------------------
static func h4d26(g: Game, e: Enemy) -> void:
	if not e.v.has("init"):
		e.owns_death = true
		e.set_hitbox(0x30, 0x2E)
		e.v = {"init": true, "intro": 300, "locked": false, "alive": true, "fire_a": 0x0A00, "fire_b": 0x0A00,
			"fire_c": 0x1000, "mouth": 0, "dying": false}
		e.hit_w = 0x30
		e.hit_h = 0x2E
	var v := e.v
	if not v["locked"]:
		g.scroll_locked = true
		v["locked"] = true
		e.hp = 0x50
	e.flash = 0
	if v["dying"]:
		v["dying_t"] -= 1
		if v["dying_t"] <= 0:
			g.scroll_locked = false
			g.phase_event = 2
			e.dead = true
			e.killed = true
		return
	if v["intro"] > 0:
		v["intro"] -= 1
		e.frame = 0x0F
		Handlers.tail_draw(e)
		return
	if e.hp <= 0:
		v["dying"] = true
		v["dying_t"] = 60
		return
	if v["mouth"] > 0:
		v["mouth"] -= 1
		if v["mouth"] == 0:
			e.frame = 0x0F
	v["fire_a"] -= g.rng.randi() & 0x3F
	if v["fire_a"] < 0:
		v["fire_a"] = 0x0A00
		g.spawn_ball(e.x, e.y + 8)
		g.sfx(0x16)
		e.frame = 0x0E
		v["mouth"] = 20
	v["fire_b"] -= g.rng.randi() & 0x3F
	if v["fire_b"] < 0:
		v["fire_b"] = 0x0A00
		g.spawn_heavy(e.x, e.y + 8)
		e.frame = 0x0E
		v["mouth"] = 20
		g.sfx(0x16)
	v["fire_c"] -= g.rng.randi() & 0x3F
	if v["fire_c"] < 0:
		v["fire_c"] = 0x1000
		var b := g.spawn_native(e.x - 10, e.y + 0x1E, 0x7F, 0, Callable(HandlersL1, "h4712"), 0x10, 0x10)
		b.vy = 7.0
		g.sfx(0x12)
	Handlers.tail_draw(e)


# ---- $4FF6: flying mine layers ---------------------------------------------------------------------------
static func h4ff6(g: Game, e: Enemy) -> void:
	if not e.v.has("init"):
		e.v["init"] = true
		e.on_death = Callable(HandlersL1, "d4ff6")
	e.set_rb(0x19, e.rb(0x19) - 1)
	if not Handlers.bpl(e.rb(0x19)):
		e.set_rb(0x19, 0x0A)
		e.frame ^= 1
	Handlers.tail_path(g, e)


## $4FF6 when destroyed: drops a power-up and two pieces fly away ($513C)
static func d4ff6(g: Game, e: Enemy) -> void:
	g.drop_item(e.x + 0x14, e.y + 0x10)
	var a := g.spawn_native(e.x - 0, e.y - 8, 2, 0x2B, Callable(HandlersL1, "h513c"), 0x10, 0x10)
	a.vx = -2.83
	a.vy = 0.0
	var b := g.spawn_native(e.x + 8, e.y + 0x1E, 2, 0x2B, Callable(HandlersL1, "h513c"), 0x10, 0x10)
	b.vx = 0.0
	b.vy = -1.41


static func h513c(g: Game, e: Enemy) -> void:
	e.set_rb(0x13, e.rb(0x13) - 1)
	if not Handlers.bpl(e.rb(0x13)):
		e.set_rb(0x13, 5)
		e.frame ^= 7
	e.x += e.vx
	e.y += e.vy
	if e.x < 0.0 or e.y < 0.0 or e.x > 350.0 or e.y > 224.0:
		e.dead = true
