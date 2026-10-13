class_name M68K
extends RefCounted
## Minimal MC68000 interpreter (integer instruction set) used to run the game's own TFMX replay
## routine. Memory is a flat 512 KB chip RAM; everything at or above `mem.size()` goes to `io`.
##
##   io.io_read(addr, size) -> int      size 0 = byte, 1 = word
##   io.io_write(addr, size, value)
##
## Unimplemented opcodes push an error and stop the call (so a missing instruction is obvious).

const SENTINEL := 0xFFFFFFF0
const MASKS: Array[int] = [0xFF, 0xFFFF, 0xFFFFFFFF]
const SIGNS: Array[int] = [0x80, 0x8000, 0x80000000]
const BITS: Array[int] = [8, 16, 32]

var mem := PackedByteArray()
var msize := 0
var d := PackedInt64Array()
var a := PackedInt64Array()
var pc := 0
var fx := 0
var fn := 0
var fz := 0
var fv := 0
var fc := 0
var fs := 1
var io: Object = null
var instr_count := 0
var call_log: Dictionary = {}     # optional: target address -> count of JSR / BSR
var trace_calls := false
var failed := false
var last_error := ""

# effective address scratch (avoids allocating per access)
var _k := 0      # 0 = Dn, 1 = An, 2 = memory, 3 = immediate
var _v := 0


func _init(memory: PackedByteArray = PackedByteArray()) -> void:
	mem = memory
	msize = memory.size()
	d.resize(8)
	a.resize(8)


# ---------------------------------------------------------------- memory
func r8(ad: int) -> int:
	ad &= 0xFFFFFF
	if ad < msize:
		return mem[ad]
	return io.io_read(ad, 0) & 0xFF


func r16(ad: int) -> int:
	ad &= 0xFFFFFF
	if ad + 1 < msize:
		return (mem[ad] << 8) | mem[ad + 1]
	return io.io_read(ad, 1) & 0xFFFF


func r32(ad: int) -> int:
	ad &= 0xFFFFFF
	if ad + 3 < msize:
		return (mem[ad] << 24) | (mem[ad + 1] << 16) | (mem[ad + 2] << 8) | mem[ad + 3]
	return ((io.io_read(ad, 1) & 0xFFFF) << 16) | (io.io_read(ad + 2, 1) & 0xFFFF)


func w8(ad: int, v: int) -> void:
	ad &= 0xFFFFFF
	if ad < msize:
		mem[ad] = v & 0xFF
	else:
		io.io_write(ad, 0, v & 0xFF)


func w16(ad: int, v: int) -> void:
	ad &= 0xFFFFFF
	v &= 0xFFFF
	if ad + 1 < msize:
		mem[ad] = v >> 8
		mem[ad + 1] = v & 0xFF
	else:
		io.io_write(ad, 1, v)


func w32(ad: int, v: int) -> void:
	ad &= 0xFFFFFF
	v &= 0xFFFFFFFF
	if ad + 3 < msize:
		mem[ad] = v >> 24
		mem[ad + 1] = (v >> 16) & 0xFF
		mem[ad + 2] = (v >> 8) & 0xFF
		mem[ad + 3] = v & 0xFF
	else:
		io.io_write(ad, 1, v >> 16)
		io.io_write(ad + 2, 1, v & 0xFFFF)


func rd(ad: int, size: int) -> int:
	if size == 0:
		return r8(ad)
	if size == 1:
		return r16(ad)
	return r32(ad)


func wr(ad: int, size: int, v: int) -> void:
	if size == 0:
		w8(ad, v)
	elif size == 1:
		w16(ad, v)
	else:
		w32(ad, v)


func fetch16() -> int:
	var v := r16(pc)
	pc = (pc + 2) & 0xFFFFFFFF
	return v


func fetch32() -> int:
	var v := r32(pc)
	pc = (pc + 4) & 0xFFFFFFFF
	return v


static func sx(v: int, size: int) -> int:
	v &= MASKS[size]
	return v - (1 << BITS[size]) if (v & SIGNS[size]) != 0 else v


# ---------------------------------------------------------------- status
func get_sr() -> int:
	return (fs << 13) | (fx << 4) | (fn << 3) | (fz << 2) | (fv << 1) | fc | 0x0700


func set_sr(v: int) -> void:
	fs = (v >> 13) & 1
	fx = (v >> 4) & 1
	fn = (v >> 3) & 1
	fz = (v >> 2) & 1
	fv = (v >> 1) & 1
	fc = v & 1


func cond(cc: int) -> bool:
	match cc:
		0: return true
		1: return false
		2: return fc == 0 and fz == 0
		3: return fc == 1 or fz == 1
		4: return fc == 0
		5: return fc == 1
		6: return fz == 0
		7: return fz == 1
		8: return fv == 0
		9: return fv == 1
		10: return fn == 0
		11: return fn == 1
		12: return fn == fv
		13: return fn != fv
		14: return fz == 0 and fn == fv
	return fz == 1 or fn != fv


# ---------------------------------------------------------------- effective addresses
func _index_ea(base: int) -> int:
	var ext := fetch16()
	var disp := sx(ext & 0xFF, 0)
	var r := (ext >> 12) & 7
	var v: int = a[r] if (ext & 0x8000) != 0 else d[r]
	v = sx(v, 2) if (ext & 0x800) != 0 else sx(v, 1)
	return (base + disp + v) & 0xFFFFFFFF


func _ea(mode: int, reg: int, size: int) -> void:
	match mode:
		0:
			_k = 0
			_v = reg
		1:
			_k = 1
			_v = reg
		2:
			_k = 2
			_v = a[reg]
		3:
			var ad: int = a[reg]
			var inc := 2 if (reg == 7 and size == 0) else (1 << size)
			a[reg] = (ad + inc) & 0xFFFFFFFF
			_k = 2
			_v = ad
		4:
			var dec := 2 if (reg == 7 and size == 0) else (1 << size)
			a[reg] = (a[reg] - dec) & 0xFFFFFFFF
			_k = 2
			_v = a[reg]
		5:
			_k = 2
			_v = (a[reg] + sx(fetch16(), 1)) & 0xFFFFFFFF
		6:
			_k = 2
			_v = _index_ea(a[reg])
		_:
			if reg == 0:
				_k = 2
				_v = sx(fetch16(), 1) & 0xFFFFFFFF
			elif reg == 1:
				_k = 2
				_v = fetch32()
			elif reg == 2:
				var base := pc
				_k = 2
				_v = (base + sx(fetch16(), 1)) & 0xFFFFFFFF
			elif reg == 3:
				var base2 := pc
				_k = 2
				_v = _index_ea(base2)
			elif reg == 4:
				_k = 3
				if size == 2:
					_v = fetch32()
				else:
					var iv := fetch16()
					_v = iv & 0xFF if size == 0 else iv
			else:
				_fail("EA mode 7/%d" % reg)


func _gv(size: int) -> int:
	match _k:
		0: return d[_v] & MASKS[size]
		1: return a[_v] & MASKS[size]
		2: return rd(_v, size)
	return _v & MASKS[size]


func _pv(size: int, val: int) -> void:
	val &= MASKS[size]
	match _k:
		0:
			if size == 2:
				d[_v] = val
			elif size == 1:
				d[_v] = (d[_v] & 0xFFFF0000) | val
			else:
				d[_v] = (d[_v] & 0xFFFFFF00) | val
		1:
			a[_v] = (sx(val, size) & 0xFFFFFFFF) if size < 2 else val
		2:
			wr(_v, size, val)


func _fail(msg: String) -> void:
	failed = true
	last_error = "%s at %06X" % [msg, pc]
	push_error("M68K: " + last_error)


# ---------------------------------------------------------------- flag helpers
func _nz(r: int, size: int) -> void:
	r &= MASKS[size]
	fn = 1 if (r & SIGNS[size]) != 0 else 0
	fz = 1 if r == 0 else 0


func _add(s: int, dv: int, size: int, x: int = 0, setx: bool = true, keepz: bool = false) -> int:
	var m: int = MASKS[size]
	var r := (s & m) + (dv & m) + x
	var res := r & m
	fc = 1 if r > m else 0
	fv = 1 if ((~(s ^ dv)) & (s ^ res) & SIGNS[size]) != 0 else 0
	if keepz:
		if res != 0:
			fz = 0
	else:
		fz = 1 if res == 0 else 0
	fn = 1 if (res & SIGNS[size]) != 0 else 0
	if setx:
		fx = fc
	return res


func _sub(s: int, dv: int, size: int, x: int = 0, setx: bool = true, keepz: bool = false, is_cmp: bool = false) -> int:
	var m: int = MASKS[size]
	var r := (dv & m) - (s & m) - x
	var res := r & m
	fc = 1 if r < 0 else 0
	fv = 1 if (((s ^ dv) & (dv ^ res)) & SIGNS[size]) != 0 else 0
	if keepz:
		if res != 0:
			fz = 0
	else:
		fz = 1 if res == 0 else 0
	fn = 1 if (res & SIGNS[size]) != 0 else 0
	if setx and not is_cmp:
		fx = fc
	return res


func _push32(v: int) -> void:
	a[7] = (a[7] - 4) & 0xFFFFFFFF
	w32(a[7], v)


func _pop32() -> int:
	var v := r32(a[7])
	a[7] = (a[7] + 4) & 0xFFFFFFFF
	return v


func _pop16() -> int:
	var v := r16(a[7])
	a[7] = (a[7] + 2) & 0xFFFFFFFF
	return v


# ---------------------------------------------------------------- execution
## Runs the subroutine at `addr` until it returns. `as_interrupt` ends with RTE instead of RTS.
func call_sub(addr: int, max_instr: int = 300000, as_interrupt: bool = false) -> void:
	if failed:
		return
	if as_interrupt:
		_push32(SENTINEL)
		a[7] = (a[7] - 2) & 0xFFFFFFFF
		w16(a[7], get_sr())
	else:
		_push32(SENTINEL)
	pc = addr
	var n := 0
	while pc != SENTINEL and not failed:
		step()
		n += 1
		if n > max_instr:
			_fail("instruction budget exceeded")
			break
	instr_count += n


## Runs a subroutine like call_sub, but calls `hooks[pc]` (func(cpu: M68K)) instead of executing the
## code at those addresses (the hook must perform the RTS itself with rts()), and returns early when
## the PC reaches one of `stops`. Returns the address it stopped at (SENTINEL = normal return).
func call_hooked(addr: int, hooks: Dictionary, stops: Dictionary, max_instr: int = 20000) -> int:
	if failed:
		return SENTINEL
	_push32(SENTINEL)
	pc = addr
	var n := 0
	while pc != SENTINEL and not failed:
		if hooks.has(pc):
			hooks[pc].call(self)
			continue
		if stops.has(pc):
			break
		step()
		n += 1
		if n > max_instr:
			_fail("instruction budget exceeded in hooked call")
			break
	instr_count += n
	return pc


func rts() -> void:
	pc = _pop32()


func step() -> void:
	var op := fetch16()
	match op >> 12:
		0x0: _op0(op)
		0x1: _move(op, 0)
		0x2: _move(op, 2)
		0x3: _move(op, 1)
		0x4: _op4(op)
		0x5: _op5(op)
		0x6: _op6(op)
		0x7:
			var v := sx(op & 0xFF, 0) & 0xFFFFFFFF
			d[(op >> 9) & 7] = v
			_nz(v, 2)
			fv = 0
			fc = 0
		0x8: _op8(op)
		0x9: _addsub(op, false)
		0xB: _opB(op)
		0xC: _opC(op)
		0xD: _addsub(op, true)
		0xE: _opE(op)
		_: _fail("line A/F opcode %04X" % op)


func _op0(op: int) -> void:
	if (op & 0x100) != 0:
		var mode := (op >> 3) & 7
		if mode == 1:
			_fail("movep")
			return
		_bitop(op, d[(op >> 9) & 7])
		return
	var sub := (op >> 9) & 7
	if sub == 4:
		_bitop(op, fetch16() & 0xFF)
		return
	var size := (op >> 6) & 3
	if size == 3:
		_fail("op0 size3")
		return
	var imm: int
	if size == 2:
		imm = fetch32()
	else:
		imm = fetch16() & (0xFF if size == 0 else 0xFFFF)
	var mode2 := (op >> 3) & 7
	var reg := op & 7
	if mode2 == 7 and reg == 4:
		var sr := get_sr()
		var ccr := sr & 0xFF
		var base: int = sr if size == 1 else ccr
		var nv := base
		if sub == 0:
			nv = base | imm
		elif sub == 1:
			nv = base & imm
		elif sub == 5:
			nv = base ^ imm
		else:
			_fail("imm to sr")
			return
		if size == 1:
			set_sr(nv)
		else:
			set_sr((sr & 0xFF00) | (nv & 0xFF))
		return
	_ea(mode2, reg, size)
	var k := _k
	var v := _v
	var dv := _gv(size)
	var r := 0
	match sub:
		0:
			r = dv | imm
			_nz(r, size)
			fv = 0
			fc = 0
		1:
			r = dv & imm
			_nz(r, size)
			fv = 0
			fc = 0
		2:
			r = _sub(imm, dv, size)
		3:
			r = _add(imm, dv, size)
		5:
			r = dv ^ imm
			_nz(r, size)
			fv = 0
			fc = 0
		6:
			_sub(imm, dv, size, 0, false, false, true)
			return
		_:
			_fail("imm op")
			return
	_k = k
	_v = v
	_pv(size, r)


func _bitop(op: int, bit: int) -> void:
	var mode := (op >> 3) & 7
	var reg := op & 7
	var kind := (op >> 6) & 3
	if mode == 0:
		bit &= 31
		var v: int = d[reg]
		fz = 0 if ((v >> bit) & 1) != 0 else 1
		if kind == 1:
			d[reg] = v ^ (1 << bit)
		elif kind == 2:
			d[reg] = v & (~(1 << bit)) & 0xFFFFFFFF
		elif kind == 3:
			d[reg] = v | (1 << bit)
	else:
		bit &= 7
		_ea(mode, reg, 0)
		var k := _k
		var ad := _v
		var v2 := _gv(0)
		fz = 0 if ((v2 >> bit) & 1) != 0 else 1
		_k = k
		_v = ad
		if kind == 1:
			_pv(0, v2 ^ (1 << bit))
		elif kind == 2:
			_pv(0, v2 & (~(1 << bit)))
		elif kind == 3:
			_pv(0, v2 | (1 << bit))


func _move(op: int, size: int) -> void:
	_ea((op >> 3) & 7, op & 7, size)
	var v := _gv(size)
	var dmode := (op >> 6) & 7
	var dreg := (op >> 9) & 7
	if dmode == 1:
		a[dreg] = sx(v, size) & 0xFFFFFFFF
		return
	_ea(dmode, dreg, size)
	_pv(size, v)
	_nz(v, size)
	fv = 0
	fc = 0


func _op4(op: int) -> void:
	var mode := (op >> 3) & 7
	var reg := op & 7
	if (op & 0x1C0) == 0x1C0:               # LEA
		_ea(mode, reg, 2)
		a[(op >> 9) & 7] = _v
		return
	if (op & 0x1C0) == 0x180:               # CHK
		_ea(mode, reg, 1)
		_fail("CHK")
		return
	if (op & 0xFB80) == 0x4880 and mode != 0:
		_movem(op)
		return
	var hi := op & 0xFF00
	var size := (op >> 6) & 3
	if size != 3 and (hi == 0x4200 or hi == 0x4400 or hi == 0x4000 or hi == 0x4600 or hi == 0x4A00):
		_ea(mode, reg, size)
		var k := _k
		var ad := _v
		match hi:
			0x4200:         # CLR
				_pv(size, 0)
				fn = 0
				fz = 1
				fv = 0
				fc = 0
			0x4400:         # NEG
				var v := _gv(size)
				_k = k
				_v = ad
				_pv(size, _sub(v, 0, size))
			0x4000:         # NEGX
				var v2 := _gv(size)
				_k = k
				_v = ad
				_pv(size, _sub(v2, 0, size, fx, true, true))
			0x4600:         # NOT
				var r := ~_gv(size)
				_k = k
				_v = ad
				_pv(size, r)
				_nz(r, size)
				fv = 0
				fc = 0
			0x4A00:         # TST
				_nz(_gv(size), size)
				fv = 0
				fc = 0
		return
	if size == 3 and (hi == 0x4000 or hi == 0x4200 or hi == 0x4400 or hi == 0x4600):
		_ea(mode, reg, 1)
		if hi == 0x4000:
			_pv(1, get_sr())
		elif hi == 0x4400:
			set_sr((get_sr() & 0xFF00) | (_gv(1) & 0xFF))
		elif hi == 0x4600:
			set_sr(_gv(1))
		else:
			_pv(1, get_sr() & 0xFF)
		return
	if (op & 0xFFF8) == 0x4880 or (op & 0xFFF8) == 0x48C0:      # EXT
		if (op & 0x40) != 0:
			d[reg] = sx(d[reg], 1) & 0xFFFFFFFF
			_nz(d[reg], 2)
		else:
			var v3 := sx(d[reg], 0) & 0xFFFF
			d[reg] = (d[reg] & 0xFFFF0000) | v3
			_nz(v3, 1)
		fv = 0
		fc = 0
		return
	if (op & 0xFFF8) == 0x4840:                                  # SWAP
		var vv: int = d[reg]
		vv = ((vv & 0xFFFF) << 16) | (vv >> 16)
		d[reg] = vv
		_nz(vv, 2)
		fv = 0
		fc = 0
		return
	if (op & 0xFFC0) == 0x4840:                                  # PEA
		_ea(mode, reg, 2)
		_push32(_v)
		return
	if (op & 0xFFF8) == 0x4E50:                                  # LINK
		_push32(a[reg])
		a[reg] = a[7]
		a[7] = (a[7] + sx(fetch16(), 1)) & 0xFFFFFFFF
		return
	if (op & 0xFFF8) == 0x4E58:                                  # UNLK
		a[7] = a[reg]
		a[reg] = _pop32()
		return
	if op == 0x4E71:
		return
	if op == 0x4E75:
		pc = _pop32()
		return
	if op == 0x4E73:
		set_sr(_pop16())
		pc = _pop32()
		return
	if op == 0x4E77:
		set_sr((get_sr() & 0xFF00) | (_pop16() & 0xFF))
		pc = _pop32()
		return
	if (op & 0xFFC0) == 0x4E80:                                  # JSR
		_ea(mode, reg, 2)
		_push32(pc)
		pc = _v
		if trace_calls:
			call_log[pc] = call_log.get(pc, 0) + 1
		return
	if (op & 0xFFC0) == 0x4EC0:                                  # JMP
		_ea(mode, reg, 2)
		pc = _v
		return
	if (op & 0xFFF0) == 0x4E60:
		return
	if (op & 0xFFC0) == 0x4AC0:                                  # TAS
		_ea(mode, reg, 0)
		var k2 := _k
		var ad2 := _v
		var tv := _gv(0)
		_nz(tv, 0)
		fv = 0
		fc = 0
		_k = k2
		_v = ad2
		_pv(0, tv | 0x80)
		return
	_fail("op4 %04X" % op)


func _movem(op: int) -> void:
	var size := 2 if (op & 0x40) != 0 else 1
	var to_regs := (op & 0x400) != 0
	var mode := (op >> 3) & 7
	var reg := op & 7
	var mask := fetch16()
	var step_b := 4 if size == 2 else 2
	if not to_regs:
		if mode == 4:
			var ad: int = a[reg]
			for i in 16:
				if (mask & (1 << i)) != 0:
					var r := 15 - i
					ad -= step_b
					var v: int = a[r - 8] if r >= 8 else d[r]
					wr(ad, size, v)
			a[reg] = ad & 0xFFFFFFFF
		else:
			_ea(mode, reg, size)
			var ad2 := _v
			for i in 16:
				if (mask & (1 << i)) != 0:
					var v2: int = a[i - 8] if i >= 8 else d[i]
					wr(ad2, size, v2)
					ad2 += step_b
	else:
		var ad3: int
		if mode == 3:
			ad3 = a[reg]
		else:
			_ea(mode, reg, size)
			ad3 = _v
		for i in 16:
			if (mask & (1 << i)) != 0:
				var v3 := rd(ad3, size)
				if size == 1:
					v3 = sx(v3, 1) & 0xFFFFFFFF
				if i >= 8:
					a[i - 8] = v3
				else:
					d[i] = v3
				ad3 += step_b
		if mode == 3:
			a[reg] = ad3 & 0xFFFFFFFF


func _op5(op: int) -> void:
	var size := (op >> 6) & 3
	var mode := (op >> 3) & 7
	var reg := op & 7
	if size == 3:
		var cc := (op >> 8) & 0xF
		if mode == 1:                               # DBcc
			var disp := sx(fetch16(), 1)
			if not cond(cc):
				var v := (d[reg] - 1) & 0xFFFF
				d[reg] = (d[reg] & 0xFFFF0000) | v
				if v != 0xFFFF:
					pc = (pc - 2 + disp) & 0xFFFFFFFF
			return
		_ea(mode, reg, 0)                           # Scc
		_pv(0, 0xFF if cond(cc) else 0)
		return
	var q := (op >> 9) & 7
	if q == 0:
		q = 8
	if mode == 1:
		if (op & 0x100) != 0:
			a[reg] = (a[reg] - q) & 0xFFFFFFFF
		else:
			a[reg] = (a[reg] + q) & 0xFFFFFFFF
		return
	_ea(mode, reg, size)
	var k := _k
	var ad := _v
	var v2 := _gv(size)
	var r: int
	if (op & 0x100) != 0:
		r = _sub(q, v2, size)
	else:
		r = _add(q, v2, size)
	_k = k
	_v = ad
	_pv(size, r)


func _op6(op: int) -> void:
	var cc := (op >> 8) & 0xF
	var disp := op & 0xFF
	var base := pc
	if disp == 0:
		disp = sx(fetch16(), 1)
	elif disp == 0xFF:
		disp = sx(fetch32(), 2)
	else:
		disp = sx(disp, 0)
	if cc == 1:
		_push32(pc)
		pc = (base + disp) & 0xFFFFFFFF
		if trace_calls:
			call_log[pc] = call_log.get(pc, 0) + 1
	elif cond(cc):
		pc = (base + disp) & 0xFFFFFFFF


func _op8(op: int) -> void:
	var dn := (op >> 9) & 7
	var mode := (op >> 3) & 7
	var reg := op & 7
	var size := (op >> 6) & 3
	if size == 3:                                   # DIVU / DIVS
		_ea(mode, reg, 1)
		var dv := _gv(1)
		if dv == 0:
			_fail("divide by zero")
			return
		var q: int
		var rem: int
		if (op & 0x100) != 0:
			var aa := sx(d[dn], 2)
			var bb := sx(dv, 1)
			q = absi(aa) / absi(bb)
			if (aa < 0) != (bb < 0):
				q = -q
			rem = aa - q * bb
			if q > 32767 or q < -32768:
				fv = 1
				fn = 1
				return
		else:
			q = d[dn] / dv
			rem = d[dn] % dv
			if q > 0xFFFF:
				fv = 1
				fn = 1
				return
		d[dn] = ((rem & 0xFFFF) << 16) | (q & 0xFFFF)
		_nz(q, 1)
		fv = 0
		fc = 0
		return
	if (op & 0x1F0) == 0x100:
		_fail("sbcd")
		return
	_ea(mode, reg, size)
	var r: int
	if (op & 0x100) != 0:
		var k := _k
		var ad := _v
		r = d[dn] | _gv(size)
		_k = k
		_v = ad
		_pv(size, r)
	else:
		r = _gv(size) | d[dn]
		_k = 0
		_v = dn
		_pv(size, r)
	_nz(r, size)
	fv = 0
	fc = 0


func _opC(op: int) -> void:
	var dn := (op >> 9) & 7
	var mode := (op >> 3) & 7
	var reg := op & 7
	var size := (op >> 6) & 3
	if size == 3:                                   # MULU / MULS
		_ea(mode, reg, 1)
		var s := _gv(1)
		var r: int
		if (op & 0x100) != 0:
			r = (sx(d[dn], 1) * sx(s, 1)) & 0xFFFFFFFF
		else:
			r = ((d[dn] & 0xFFFF) * s) & 0xFFFFFFFF
		d[dn] = r
		_nz(r, 2)
		fv = 0
		fc = 0
		return
	if (op & 0x1F0) == 0x100:
		_fail("abcd")
		return
	var m := op & 0x1F8
	if m == 0x140:
		var t: int = d[dn]
		d[dn] = d[reg]
		d[reg] = t
		return
	if m == 0x148:
		var t2: int = a[dn]
		a[dn] = a[reg]
		a[reg] = t2
		return
	if m == 0x188:
		var t3: int = d[dn]
		d[dn] = a[reg]
		a[reg] = t3
		return
	_ea(mode, reg, size)
	var r2: int
	if (op & 0x100) != 0:
		var k := _k
		var ad := _v
		r2 = d[dn] & _gv(size)
		_k = k
		_v = ad
		_pv(size, r2)
	else:
		r2 = _gv(size) & d[dn]
		_k = 0
		_v = dn
		_pv(size, r2)
	_nz(r2, size)
	fv = 0
	fc = 0


func _addsub(op: int, is_add: bool) -> void:
	var dn := (op >> 9) & 7
	var mode := (op >> 3) & 7
	var reg := op & 7
	var size := (op >> 6) & 3
	if size == 3:                                   # ADDA / SUBA
		var sz := 2 if (op & 0x100) != 0 else 1
		_ea(mode, reg, sz)
		var v := sx(_gv(sz), sz) & 0xFFFFFFFF
		if is_add:
			a[dn] = (a[dn] + v) & 0xFFFFFFFF
		else:
			a[dn] = (a[dn] - v) & 0xFFFFFFFF
		return
	if (op & 0x130) == 0x100 and mode < 2:          # ADDX / SUBX
		if mode == 0:
			var s: int = d[reg]
			var dv: int = d[dn]
			var r: int
			if is_add:
				r = _add(s, dv, size, fx, true, true)
			else:
				r = _sub(s, dv, size, fx, true, true)
			_k = 0
			_v = dn
			_pv(size, r)
		else:
			_ea(4, reg, size)
			var s2 := _gv(size)
			_ea(4, dn, size)
			var k := _k
			var ad := _v
			var d2 := _gv(size)
			var r2: int
			if is_add:
				r2 = _add(s2, d2, size, fx, true, true)
			else:
				r2 = _sub(s2, d2, size, fx, true, true)
			_k = k
			_v = ad
			_pv(size, r2)
		return
	_ea(mode, reg, size)
	if (op & 0x100) != 0:                           # Dn op <ea> -> <ea>
		var k2 := _k
		var ad2 := _v
		var s3: int = d[dn]
		var d3 := _gv(size)
		var r3: int
		if is_add:
			r3 = _add(s3, d3, size)
		else:
			r3 = _sub(s3, d3, size)
		_k = k2
		_v = ad2
		_pv(size, r3)
	else:
		var s4 := _gv(size)
		var d4: int = d[dn]
		var r4: int
		if is_add:
			r4 = _add(s4, d4, size)
		else:
			r4 = _sub(s4, d4, size)
		_k = 0
		_v = dn
		_pv(size, r4)


func _opB(op: int) -> void:
	var dn := (op >> 9) & 7
	var mode := (op >> 3) & 7
	var reg := op & 7
	var size := (op >> 6) & 3
	if size == 3:                                   # CMPA
		var sz := 2 if (op & 0x100) != 0 else 1
		_ea(mode, reg, sz)
		var v := sx(_gv(sz), sz) & 0xFFFFFFFF
		_sub(v, a[dn], 2, 0, false, false, true)
		return
	if (op & 0x100) != 0:
		if mode == 1:                               # CMPM
			_ea(3, reg, size)
			var s := _gv(size)
			_ea(3, dn, size)
			var dv := _gv(size)
			_sub(s, dv, size, 0, false, false, true)
			return
		_ea(mode, reg, size)                        # EOR
		var k := _k
		var ad := _v
		var r := _gv(size) ^ d[dn]
		_k = k
		_v = ad
		_pv(size, r)
		_nz(r, size)
		fv = 0
		fc = 0
		return
	_ea(mode, reg, size)
	_sub(_gv(size), d[dn], size, 0, false, false, true)


func _opE(op: int) -> void:
	var size := (op >> 6) & 3
	if size == 3:
		var mode := (op >> 3) & 7
		var reg := op & 7
		_ea(mode, reg, 1)
		var k := _k
		var ad := _v
		var v := _gv(1)
		var r := _shift((op >> 9) & 3, (op & 0x100) != 0, v, 1, 1)
		_k = k
		_v = ad
		_pv(1, r)
		return
	var rr := op & 7
	var kind := (op >> 3) & 3
	var left := (op & 0x100) != 0
	var cnt := (op >> 9) & 7
	if (op & 0x20) != 0:
		cnt = d[cnt] & 63
	elif cnt == 0:
		cnt = 8
	var v2: int = d[rr] & MASKS[size]
	var res := _shift(kind, left, v2, cnt, size)
	_k = 0
	_v = rr
	_pv(size, res)


func _shift(kind: int, left: bool, v: int, cnt: int, size: int) -> int:
	var m: int = MASKS[size]
	var sg: int = SIGNS[size]
	v &= m
	if cnt == 0:
		_nz(v, size)
		fc = fx if kind == 2 else 0
		fv = 0
		return v
	var c := 0
	var vflag := 0
	for _i in cnt:
		match kind:
			0:
				if left:
					c = 1 if (v & sg) != 0 else 0
					var nv := (v << 1) & m
					if (nv & sg) != (v & sg):
						vflag = 1
					v = nv
				else:
					c = v & 1
					v = (v >> 1) | (v & sg)
				fx = c
			1:
				if left:
					c = 1 if (v & sg) != 0 else 0
					v = (v << 1) & m
				else:
					c = v & 1
					v = v >> 1
				fx = c
			2:
				if left:
					c = 1 if (v & sg) != 0 else 0
					v = ((v << 1) | fx) & m
				else:
					c = v & 1
					v = (v >> 1) | (fx * sg)
				fx = c
			_:
				if left:
					c = 1 if (v & sg) != 0 else 0
					v = ((v << 1) | c) & m
				else:
					c = v & 1
					v = (v >> 1) | (c * sg)
	fc = c
	fv = vflag if kind == 0 else 0
	_nz(v, size)
	return v
