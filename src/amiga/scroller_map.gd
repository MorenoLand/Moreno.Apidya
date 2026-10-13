class_name ScrollerMap
extends RefCounted
## Level 5 has no map in its file: the background (ceiling and floor of the castle) is drawn by the level's
## own scroller routine, one tile column per 16 scroll steps, from two byte sequences. This runs that
## routine in the interpreter (no pixels are written) and records the tiles it blits, which gives the map
## the other levels have: 15 rows x columns of tile words (tile | 0x400 = flipped vertically).

const BASE := 0xA00
const EMPTY := 0x3FF            # a tile number past the tile area: draws nothing

var _cpu: M68K
var _chip: Chipset
var _hooks := {}
var _def: Dictionary
var _init_phase := true
var _words := {}                # row * 4096 + col -> tile word
var _max_col := 0


func _hk_rts(c: M68K) -> void:
	c.rts()


## Returns {"words": PackedInt32Array (15 * cols), "cols": int}. Generating takes several seconds, so the
## result is kept in user:// keyed by a hash of the level file.
static func generate(raw: PackedByteArray, def: Dictionary, syms: Dictionary) -> Dictionary:
	var key := hash(raw)
	var path := "user://cache/map_v2_%d.bin" % key
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null and f.get_32() == 0x4D415031:
			var cols := f.get_32()
			var n := LevelData.ROWS * cols
			if n > 0 and f.get_length() == 8 + n * 4:
				var words := PackedInt32Array()
				words.resize(n)
				for i in n:
					words[i] = f.get_32()
				return {"words": words, "cols": cols}
	var g := ScrollerMap.new()
	var res: Dictionary = g._run(raw, def, syms)
	DirAccess.make_dir_recursive_absolute("user://cache")
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out != null:
		out.store_32(0x4D415031)
		out.store_32(int(res["cols"]))
		for w in res["words"]:
			out.store_32(int(w))
	return res


func _run(raw: PackedByteArray, def: Dictionary, syms: Dictionary) -> Dictionary:
	_def = def
	var mem := PackedByteArray()
	mem.resize(0x80000)
	for i in raw.size():
		mem[BASE + i] = raw[i]
	_cpu = M68K.new(mem)
	_chip = Chipset.new()
	_chip.cpu = _cpu
	_chip.perform_blits = false
	_chip.on_blit = Callable(self, "_on_blit")
	_cpu.io = _chip
	_cpu.a[7] = 0x7FFE0
	_cpu.set_sr(0x2000)
	_cpu.a[5] = 0xDFF000
	for a in range(0x4DE00, 0x4DE80, 2):
		_hooks[a] = Callable(self, "_hk_rts")      # the music routine is not loaded
	for k in ["sfx", "music"]:
		if syms.has(k):
			_hooks[int(syms[k])] = Callable(self, "_hk_rts")
	var stops := {int(def["main"]): true}
	_init_phase = true
	_cpu.call_hooked(int(def["init"]), _hooks, stops, 20000000)
	_init_phase = false
	var col_var: int = def["col_var"]
	var end_col: int = def["end_col"]
	var guard := 0
	# the picture goes on while a guardian holds the column counter: some spare columns
	var spare: int = int(_def.get("spare", 800))
	while _cpu.r16(col_var) < end_col + 22 + spare and guard < 80000 and not _cpu.failed:
		_cpu.a[5] = 0xDFF000
		_cpu.call_hooked(int(def["step"]), _hooks, {}, 100000)
		guard += 1
	var cols := _max_col + 1
	var words := PackedInt32Array()
	words.resize(LevelData.ROWS * cols)
	for i in words.size():
		words[i] = EMPTY
	for k in _words:
		var row: int = int(k) / 4096
		var col: int = int(k) % 4096
		if row < LevelData.ROWS and col < cols:
			words[row * cols + col] = _words[k]
	return {"words": words, "cols": cols}


func _on_blit(regs: Dictionary) -> void:
	if (int(regs.get(Blitter.CON0, 0)) & 0xFFF) != 0x9F0:
		return
	var size: int = int(regs.get(Blitter.SIZE, 0))
	var flip := size == 0x401
	if size != 0x401 and size != int(_def["tile_size"]):
		return
	var a := Blitter._pt(regs, Blitter.APTH, Blitter.APTL)
	var d := Blitter._pt(regs, Blitter.DPTH, Blitter.DPTL)
	var tile_bytes: int = _def["tile_bytes"]
	var t_off := a - int(_def["tiles"])
	if t_off < 0 or t_off >= 1024 * tile_bytes:
		return
	var within := t_off % tile_bytes
	var amod := Blitter._s16(int(regs.get(Blitter.AMOD, 0)))
	if flip:
		# the four one-plane blits of a flipped tile: only the first one is the tile
		if within != 0 and within != tile_bytes - 8:
			return
	elif within != 0:
		return
	var tile := t_off / tile_bytes
	var stride: int = _def["row_bytes"]
	var off := d & 0xFFFF
	var y_top := off
	var col: int
	var y_px: int
	if _init_phase:
		if flip and amod > 0:
			y_top = off - 15 * stride
		y_px = y_top / stride
		col = (y_top % stride) / 2
	else:
		var p := _cpu.r16(int(_def["ptr_var"]) + 2)
		var right: int = _def["right"]
		if flip and amod > 0:
			y_top = off - 15 * stride
		y_px = (y_top - p - right) / stride
		col = (p + right) / 2
	if y_px < 0 or (y_px & 15) != 0:
		return
	var row := y_px >> 4
	_words[row * 4096 + col] = tile | (0x400 if flip else 0)
	_max_col = maxi(_max_col, col)
