class_name HandlerVM
extends RefCounted
## Runs the original's native enemy handlers (types 4 and 5: shooters, guardians, set pieces) from
## the level file of the user's own disk, with the 68000 interpreter used for the music. Everything
## around them is native: the handlers only see the enemy record, a handful of engine variables
## and the engine services they call (bullets, explosions, sounds ...), which are answered by
## the game itself. Their drawing instructions and blitter writes are turned into sprites.

const RAM := 0x80000
const DRAW_FALLBACK := 0x7F000
const SCRATCH_BULLET := 0x7F800
const STACK_TOP := 0x7FFE0
const DRAW_RECORD := 22


## Blitter / custom chip registers seen by the handlers.
class ChipIO extends RefCounted:
	var vm: HandlerVM
	var regs := {}
	var beam := 0x10000

	func io_read(addr: int, size: int) -> int:
		var a := addr & 0x1FE
		match a:
			0x004:
				# VPOSR / VHPOSR as a long: a beam that moves, so that waits for a line end
				beam = (beam + 0x100) & 0x1FF00
				return (beam >> 16) & 0xFFFF if size == 2 and (addr & 2) == 0 else beam & 0xFFFF
			0x006:
				return vm.g.rng.randi() & 0xFFFF       # VHPOSR: used as a random number
			0x002:
				return 0                                  # DMACONR: blitter never busy
		return 0

	func io_write(addr: int, size: int, value: int) -> void:
		var a := addr & 0x1FE
		regs[a] = value & 0xFFFF
		if a == 0x058:
			vm.blit_started()


var g: Game
var level: LevelData
var syms: Dictionary
var cpu: M68K
var io := ChipIO.new()
var hooks := {}
var stops := {}
var slots: Array = []
var _blits: Array = []
var _bullet_for_scratch: Dictionary = {}
var ok := false
var rec_size := 0x20
var hp_mask := 0x7F
var unhooked := {}
var draw_base := DRAW_FALLBACK
var _pending: Array = []        # draw records the handler flushed through the engine's list processor


func _init(game: Game, lv: LevelData, level_no: int) -> void:
	g = game
	level = lv
	syms = VmSymbols.get_symbols(level_no)
	if syms.is_empty():
		return
	var mem := PackedByteArray()
	mem.resize(RAM)
	var n := mini(lv.raw.size(), RAM - LevelDefs.RAM_BASE)
	for i in n:
		mem[LevelDefs.RAM_BASE + i] = lv.raw[i]
	cpu = M68K.new(mem)
	io.vm = self
	cpu.io = io
	cpu.a[7] = STACK_TOP
	cpu.set_sr(0x2000)
	rec_size = int(syms.get("rec_size", 0x20))
	hp_mask = int(syms.get("hp_mask", 0x7F))
	hooks[syms["fire_dir"]] = Callable(self, "_hk_fire_dir")
	hooks[syms["fire_vel"]] = Callable(self, "_hk_fire_vel")
	hooks[syms["fire_aimed"]] = Callable(self, "_hk_fire_aimed")
	hooks[syms["ball"]] = Callable(self, "_hk_ball")
	hooks[syms["heavy"]] = Callable(self, "_hk_heavy")
	hooks[syms["item"]] = Callable(self, "_hk_item")
	hooks[syms["explode"]] = Callable(self, "_hk_explode")
	hooks[syms["spark"]] = Callable(self, "_hk_explode")
	hooks[syms["sfx"]] = Callable(self, "_hk_sfx")
	if syms.has("music"):
		hooks[syms["music"]] = Callable(self, "_hk_music")
	if syms.has("hit_shots"):
		hooks[syms["hit_shots"]] = Callable(self, "_hk_hit_shots")
	if syms.has("hit_bomb"):
		hooks[syms["hit_bomb"]] = Callable(self, "_hk_hit_bomb")
	if syms.has("hit_blast"):
		hooks[syms["hit_blast"]] = Callable(self, "_hk_hit_blast")
	hooks[syms["score"]] = Callable(self, "_hk_score")
	draw_base = int(syms.get("draw_base", DRAW_FALLBACK))
	if syms.has("draw_list"):
		hooks[syms["draw_list"]] = Callable(self, "_hk_draw_list")
	if syms.has("draw_main"):
		hooks[syms["draw_main"]] = Callable(self, "_hk_draw_main")
	stops[syms["loop_end"]] = true
	stops[syms["death"]] = true
	var base: int = syms["enemy_list"]
	var cnt: int = syms["enemy_slots"]
	for i in cnt:
		slots.append(null)
	cpu.w16(base + cnt * rec_size, 0xFFFF)
	ok = true


# ---- slots -----------------------------------------------------------------------------------------
func bind(e: Enemy) -> bool:
	if not ok:
		return false
	for i in slots.size():
		if slots[i] == null:
			slots[i] = e
			e.vm_slot = i
			var head := cpu.r16(int(syms["head"]))
			e._off0 = (e._off0 + head) & 0xFFFF
			if e.type == 5:
				e.set_rw(0x1E, (e.rw(0x1E) + head) & 0xFFFF)   # the spawner adds the buffer head
			_write_record(e)
			return true
	return false


func release(e: Enemy) -> void:
	if e.vm_slot >= 0 and e.vm_slot < slots.size() and slots[e.vm_slot] == e:
		slots[e.vm_slot] = null
		cpu.w16(_addr(e.vm_slot), 0)
	e.vm_slot = -1


## Low word of the playfield buffer pointer ($7B98): added to every playfield offset by the original.
func head() -> int:
	return cpu.r16(int(syms["head"]))


func slot_addr(slot: int) -> int:
	return _addr(slot)


func _addr(slot: int) -> int:
	return int(syms["enemy_list"]) + slot * rec_size


func _write_record(e: Enemy) -> void:
	var a := _addr(e.vm_slot)
	cpu.w16(a, (e.flags << 9) | e.type)
	cpu.w16(a + 2, int(e.x))
	cpu.w16(a + 4, int(e.y))
	cpu.w16(a + 6, e.group & 0xFFFF)
	cpu.w8(a + 8, (e.hp & hp_mask) | e.hp_bits | (0x80 if e.flash_bit else 0))
	cpu.w8(a + 9, e.frame)
	cpu.w8(a + 0x0A, e.hit_w)
	cpu.w8(a + 0x0B, e.hit_h)
	for o in range(0x0C, rec_size):
		cpu.w8(a + o, e.rec[o])


func _read_record(e: Enemy) -> void:
	var a := _addr(e.vm_slot)
	var tw := cpu.r16(a)
	e.type = tw & 0x1FF
	e.flags = tw >> 9
	e.x = float(_s16(cpu.r16(a + 2)))
	e.y = float(_s16(cpu.r16(a + 4)))
	var h := cpu.r8(a + 8)
	e.hp = h & hp_mask
	e.hp_bits = h & 0x7F & ~hp_mask
	e.flash_bit = (h & 0x80) != 0
	e.frame = cpu.r8(a + 9)
	e.hit_w = cpu.r8(a + 0x0A)
	e.hit_h = cpu.r8(a + 0x0B)
	for o in range(0x0C, rec_size):
		e.rec[o] = cpu.r8(a + o)
	e.group = _s16(cpu.r16(a + 6))
	e.score = Enemy._bcd(e.rw(0x1A))
	e.set_piece = e.type == 5
	if tw == 0:
		e.vm_freed = true


static func _s16(v: int) -> int:
	return v - 65536 if v >= 32768 else v


# ---- one frame of one enemy ---------------------------------------------------------------------------
func _set_globals() -> void:
	cpu.w16(syms["player_x"], g.px)
	cpu.w16(syms["player_y"], g.py)
	cpu.w16(syms["scroll_step"], g.scroll_step())
	if syms.has("col_counter"):
		cpu.w16(syms["col_counter"], g.col_counter())
	if syms.has("lock_byte"):
		cpu.w8(syms["scroll_lock"], 1 if g.scroll_locked else 0)
	else:
		cpu.w16(syms["scroll_lock"], 1 if g.scroll_locked else 0)
	cpu.w16(0x9C4, g.difficulty())
	cpu.w8(syms["heavy_frame"], 0x15 + ((g.tick >> 2) & 1))


func step(e: Enemy) -> void:
	if not ok or e.vm_slot < 0:
		return
	_write_record(e)
	_set_globals()
	var a := _addr(e.vm_slot)
	_blits.clear()
	_pending.clear()
	_bullet_for_scratch = {}
	for i in 8:
		cpu.d[i] = 0
	cpu.a[0] = a
	cpu.a[5] = 0xDFF000
	cpu.a[6] = draw_base
	cpu.a[7] = STACK_TOP
	var handler := cpu.r16(a + 0x1C)
	cpu.call_hooked(handler, hooks, stops)
	if cpu.failed:
		push_warning("handler VM failed at %X (handler %04X, type %d, rec %s): %s" % [cpu.pc, handler, e.type,
				cpu.r8(a + 8), cpu.last_error])
		cpu.failed = false
		e.dead = true
		return
	var draw_end := int(cpu.a[6])
	_apply_scratch_bullet()
	_read_record(e)
	_collect_draws(e, draw_end)
	e.vm_blits = _blits.duplicate()
	_adopt_new()
	_sync_engine_state()


## What the original's section routine ($99BE and friends) puts back in the engine variables when the next
## part of the level starts: the per-tick routines of the guardian, the column freeze and the lock.
func section_reset() -> void:
	if not ok:
		return
	for key in ["scene_a", "scene_b"]:
		if syms.has(key):
			cpu.w32(int(syms[key]), 0)
	if syms.has("col_freeze"):
		cpu.w8(int(syms["col_freeze"]), 0)
	g.col_frozen = false
	if syms.has("lock_byte"):
		cpu.w8(int(syms["scroll_lock"]), 0)
	else:
		cpu.w16(int(syms["scroll_lock"]), 0)


## Phase events and the scroll lock are written by the handlers.
func _sync_engine_state() -> void:
	if syms.has("lock_byte"):
		g.scroll_locked = cpu.r8(syms["scroll_lock"]) != 0
	else:
		g.scroll_locked = cpu.r16(syms["scroll_lock"]) != 0
	if syms.has("col_freeze"):
		g.col_frozen = cpu.r8(syms["col_freeze"]) != 0
	if syms.has("col_counter"):
		g.col_set_by_handler(cpu.r16(syms["col_counter"]))
	var pa := cpu.r16(syms["phase_a"])
	if pa != 0:
		g.phase_event = pa
		cpu.w16(syms["phase_a"], 0)


## The routines the main loop calls every tick through two pointers (boss fights, end sequences). They
## draw into the owner's parts like a handler does.
func run_scene(owner: Enemy) -> void:
	if not ok or not syms.has("scene_a"):
		return
	owner.vm_draws.clear()
	owner.vm_blits.clear()
	var ran := false
	for key in ["scene_a", "scene_b"]:
		if not syms.has(key):
			continue
		var target := cpu.r32(int(syms[key])) & 0xFFFFFF
		if target < LevelDefs.RAM_BASE or target >= LevelDefs.RAM_BASE + level.raw.size():
			continue
		ran = true
		_blits.clear()
		_pending.clear()
		_bullet_for_scratch = {}
		_set_globals()
		for i in 8:
			cpu.d[i] = 0
		cpu.a[5] = 0xDFF000
		cpu.a[6] = draw_base
		cpu.a[7] = STACK_TOP
		cpu.call_hooked(target, hooks, stops)
		if cpu.failed:
			push_warning("scene routine failed at %X (routine %X): %s" % [cpu.pc, target, cpu.last_error])
			cpu.failed = false
			cpu.w32(int(syms[key]), 0)
			continue
		var draw_end := int(cpu.a[6])
		_apply_scratch_bullet()
		var n := (draw_end - draw_base) / DRAW_RECORD
		for d in _pending:
			owner.vm_draws.append(d)
		for i in clampi(n, 0, 40):
			var dr: Variant = _make_draw(draw_base + i * DRAW_RECORD)
			if dr != null:
				owner.vm_draws.append(dr)
		for b in _blits:
			owner.vm_blits.append(b)
		_pending.clear()
		_adopt_new()
	if ran:
		_sync_engine_state()


func _collect_draws(e: Enemy, draw_end: int) -> void:
	var n := (draw_end - draw_base) / DRAW_RECORD
	e.vm_draws.clear()
	for d in _pending:
		e.vm_draws.append(d)
	_pending.clear()
	for i in clampi(n, 0, 40):
		var d: Variant = _make_draw(draw_base + i * DRAW_RECORD)
		if d != null:
			e.vm_draws.append(d)


## The 22 byte draw record at r as a sprite request (null when it is unused or not an image).
func _make_draw(r: int) -> Variant:
	var flags := cpu.r16(r)
	if flags == 0 or (flags & 0x8000) != 0:
		return null
	var w9 := cpu.r16(r + 18)
	var rows := cpu.r16(r + 2)
	var gfx := cpu.r32(r + 8)
	var mask := cpu.r32(r + 12)
	var wd := w9 - 1
	if rows < 1 or rows > 200 or wd < 1 or wd > 8:
		return null
	if gfx < LevelDefs.RAM_BASE or gfx >= LevelDefs.RAM_BASE + level.raw.size():
		return null
	return {"flags": flags, "x": _s16(cpu.r16(r + 4)), "y": _s16(cpu.r16(r + 6)),
		"gfx": gfx, "mask": mask, "w": wd, "rows": rows}


## The engine's draw list processor ($24D6 in level 2, called with a private list in A0): the records are
## drawn like the ones the handler puts into its own list.
func _hk_draw_list(c: M68K) -> void:
	_flush_list(int(c.a[0]), false)
	c.rts()


## The same processor with the main list, called by handlers that draw twice in a tick: what they
## appended so far is taken over (and cleared, the list is built again from the start of the list).
func _hk_draw_main(c: M68K) -> void:
	_flush_list(draw_base, true)
	c.rts()


func _flush_list(a: int, clear: bool) -> void:
	for i in 40:
		var flags := cpu.r16(a)
		if (flags & 0x8000) != 0:
			break
		if flags != 0:
			var d: Variant = _make_draw(a)
			if d != null:
				_pending.append(d)
			if clear:
				cpu.w16(a, 0)
		a += DRAW_RECORD


# ---- new records written by handlers --------------------------------------------------------------------
func _adopt_new() -> void:
	var cnt: int = slots.size()
	for i in cnt:
		if slots[i] != null:
			continue
		var a := _addr(i)
		var tw := cpu.r16(a)
		if tw == 0 or tw == 0xFFFF:
			continue
		var e := g.adopt_vm_enemy(self, i)
		if e != null:
			slots[i] = e
			e.vm_slot = i
			e._off0 = cpu.r16(int(syms["head"]))
			_read_record(e)
		else:
			cpu.w16(a, 0)


# ---- blitter ---------------------------------------------------------------------------------------------
func blit_started() -> void:
	var r := io.regs
	var con0: int = int(r.get(0x040, 0))
	var size: int = int(r.get(0x058, 0))
	var a: int = ((int(r.get(0x050, 0)) & 0xFFFF) << 16) | (int(r.get(0x052, 0)) & 0xFFFF)
	var b: int = ((int(r.get(0x04C, 0)) & 0xFFFF) << 16) | (int(r.get(0x04E, 0)) & 0xFFFF)
	var d: int = ((int(r.get(0x054, 0)) & 0xFFFF) << 16) | (int(r.get(0x056, 0)) & 0xFFFF)
	var h := size >> 6
	var w := size & 63
	if w == 0:
		w = 64
	_blits.append({"con0": con0, "a": a, "b": b, "dst_off": d & 0xFFFF, "h": h, "w": w})


# ---- hooks (engine services) ----------------------------------------------------------------------------------
func _hk_fire_dir(c: M68K) -> void:
	var x := _s16(c.d[0] & 0xFFFF)
	var y := _s16(c.d[1] & 0xFFFF)
	var word := c.d[2] & 0xFFFF
	var b := g.fire_dir(float(x), float(y), word)
	# the original leaves A0 on the new bullet record, which some handlers patch (velocity words)
	for i in 16:
		c.w8(SCRATCH_BULLET + i, 0)
	_bullet_for_scratch = {"bullet": b}
	c.a[0] = SCRATCH_BULLET
	c.rts()


func _apply_scratch_bullet() -> void:
	if _bullet_for_scratch.is_empty():
		return
	var b = _bullet_for_scratch.get("bullet")
	if b == null:
		return
	var va := _s16(cpu.r16(SCRATCH_BULLET + 0x0A))
	var vb := _s16(cpu.r16(SCRATCH_BULLET + 0x0C))
	if va != 0 or vb != 0:
		b["vx"] = float(va) / 256.0
		b["vy"] = float(vb) / 256.0


func _hk_fire_vel(c: M68K) -> void:
	g.fire_vel(float(_s16(c.d[0] & 0xFFFF)), float(_s16(c.d[1] & 0xFFFF)), _s32(c.d[2]), _s32(c.d[3]),
			int(syms.get("vel_shift", 9)), int(syms.get("aim_scale", 1)) != 0)
	c.rts()


func _hk_fire_aimed(c: M68K) -> void:
	var a := c.a[0]
	var x := _s16(c.r16(a + 2)) + _s8(c.r8(a + 0x14))
	var y := _s16(c.r16(a + 4)) + _s8(c.r8(a + 0x15))
	g.fire_aimed(float(x), float(y), int(syms.get("aim_guard", 1)) != 0, int(syms.get("aim_scale", 1)) != 0)
	c.rts()


func _hk_ball(c: M68K) -> void:
	g.spawn_ball(float(_s16(c.d[0] & 0xFFFF)), float(_s16(c.d[1] & 0xFFFF)))
	c.rts()


func _hk_heavy(c: M68K) -> void:
	g.spawn_heavy(float(_s16(c.d[0] & 0xFFFF)), float(_s16(c.d[1] & 0xFFFF)))
	c.rts()


func _hk_item(c: M68K) -> void:
	g.drop_item(float(_s16(c.d[0] & 0xFFFF)), float(_s16(c.d[1] & 0xFFFF)))
	c.rts()


func _hk_explode(c: M68K) -> void:
	g.explode(float(_s16(c.d[0] & 0xFFFF)), float(_s16(c.d[1] & 0xFFFF)))
	# the original returns the new explosion record in A1 and some callers patch it (frame words)
	for i in 16:
		c.w8(SCRATCH_BULLET + 0x40 + i, 0)
	c.a[1] = SCRATCH_BULLET + 0x40
	c.rts()


func _hk_sfx(c: M68K) -> void:
	g.sfx(c.d[0] & 0xFF)
	c.rts()


## The collision routines of handlers that test the player's shots against their parts: the box is
## (D0,D1)-(D2,D3), the result is the damage in D5 (and the zero flag).
var dbg_hit_calls := 0
var dbg_box: Array = []
var dbg_hits := 0


func _hit_result(c: M68K, damage: int) -> void:
	dbg_hit_calls += 1
	if damage > 0:
		dbg_hits += 1
	c.d[4] = 0
	c.d[5] = damage
	c.fz = 1 if damage == 0 else 0
	c.fn = 0
	c.rts()


func _box(c: M68K) -> Array:
	return [_s16(c.d[0] & 0xFFFF), _s16(c.d[1] & 0xFFFF), _s16(c.d[2] & 0xFFFF), _s16(c.d[3] & 0xFFFF)]


func _hk_hit_shots(c: M68K) -> void:
	var b := _box(c)
	dbg_box = b
	_hit_result(c, g.shots_in_box(b[0], b[1], b[2], b[3]))


func _hk_hit_bomb(c: M68K) -> void:
	var b := _box(c)
	_hit_result(c, g.bomb_in_box(b[0], b[1], b[2], b[3]))


func _hk_hit_blast(c: M68K) -> void:
	var b := _box(c)
	_hit_result(c, g.blast_in_box(b[0], b[1], b[2], b[3]))


func _hk_music(c: M68K) -> void:
	g.play_song(c.d[0] & 0xFFFF)
	c.rts()


func _hk_score(c: M68K) -> void:
	g.add_score_bcd(c.d[0] & 0xFFFF)
	c.rts()


static func _s8(v: int) -> int:
	return v - 256 if v >= 128 else v


static func _s32(v: int) -> int:
	v &= 0xFFFFFFFF
	return v - 0x100000000 if v >= 0x80000000 else v
