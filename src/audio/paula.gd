class_name Paula
extends RefCounted
## Model of the Amiga's four-channel DMA audio (Paula) as far as the TFMX replayer needs it:
## AUDxLC/LEN/PER/VOL, DMACON, INTENA/INTREQ and the end-of-block audio interrupt.
## Acts as the M68K's I/O handler (custom chip registers at $DFF000).

const PAL_CLOCK := 3546895.0

var cpu: M68K
var rate := 44100.0
var dmacon := 0
var intena := 0
var intreq := 0
var _regs := PackedInt32Array()
var _vh := 0

var lc := PackedInt32Array([0, 0, 0, 0])
var ln := PackedInt32Array([1, 1, 1, 1])
var per := PackedInt32Array([0, 0, 0, 0])
var vol := PackedInt32Array([0, 0, 0, 0])
var on := PackedByteArray([0, 0, 0, 0])
var ptr := PackedInt32Array([0, 0, 0, 0])
var pos := PackedInt32Array([0, 0, 0, 0])
var words := PackedInt32Array([0, 0, 0, 0])
var acc := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var step := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])


func _init() -> void:
	_regs.resize(256)


func set_rate(r: float) -> void:
	rate = r
	for i in 4:
		_recalc(i)


func _recalc(ch: int) -> void:
	var p := per[ch] if per[ch] >= 124 else 124
	step[ch] = PAL_CLOCK / (float(p) * rate)


# ---- M68K I/O interface -----------------------------------------------------------------------
func io_write(addr: int, size: int, value: int) -> void:
	if addr < 0xDFF000 or addr >= 0xE00000:
		return
	var reg := addr & 0x1FE
	if size == 0:
		var old := _regs[reg >> 1]
		if (addr & 1) == 0:
			value = (old & 0x00FF) | (value << 8)
		else:
			value = (old & 0xFF00) | value
	_regs[reg >> 1] = value & 0xFFFF
	if reg >= 0xA0 and reg < 0xE0:
		var ch := (reg - 0xA0) >> 4
		match reg & 0xF:
			0:
				lc[ch] = ((value & 7) << 16) | (lc[ch] & 0xFFFF)
			2:
				lc[ch] = (lc[ch] & 0x70000) | (value & 0xFFFE)
			4:
				ln[ch] = value if value != 0 else 65536
			6:
				per[ch] = value
				_recalc(ch)
			8:
				vol[ch] = 64 if (value & 0x40) != 0 else (value & 0x3F)
	elif reg == 0x96:
		if (value & 0x8000) != 0:
			dmacon |= value & 0x7FFF
		else:
			dmacon &= ~value
		_update_dma()
	elif reg == 0x9A:
		if (value & 0x8000) != 0:
			intena |= value & 0x7FFF
		else:
			intena &= ~value
	elif reg == 0x9C:
		if (value & 0x8000) != 0:
			intreq |= value & 0x7FFF
		else:
			intreq &= ~value


func io_read(addr: int, size: int) -> int:
	var reg := addr & 0x1FE
	var v := 0
	match reg:
		0x1E: v = intreq
		0x1C: v = intena
		0x02: v = dmacon
		0x04, 0x06:
			_vh = (_vh + 7) & 0xFFFF
			v = _vh
		_: v = _regs[reg >> 1]
	if size == 0:
		return (v >> 8) & 0xFF if (addr & 1) == 0 else v & 0xFF
	return v & 0xFFFF


func _update_dma() -> void:
	var enabled := (dmacon & 0x200) != 0
	for i in 4:
		var now := enabled and (dmacon & (1 << i)) != 0
		if now and on[i] == 0:
			ptr[i] = lc[i]
			words[i] = ln[i]
			pos[i] = 0
			acc[i] = 0.0
		on[i] = 1 if now else 0


func _irq() -> void:
	var vec := cpu.r32(0x70)
	if vec != 0:
		cpu.call_sub(vec, 20000, true)


## Renders `n` stereo samples (channels 0/3 left, 1/2 right) into `out` starting at `at`.
func render(n: int, out: PackedVector2Array, at: int) -> void:
	var mem := cpu.mem
	var msize := mem.size()
	var scale := 1.0 / 16384.0
	for i in n:
		var sl := 0
		var sr := 0
		for ch in 4:
			if on[ch] == 0:
				continue
			var ad := ptr[ch] + pos[ch]
			var s := 0
			if ad < msize:
				s = mem[ad]
				if s > 127:
					s -= 256
			var v := s * vol[ch]
			if ch == 0 or ch == 3:
				sl += v
			else:
				sr += v
			acc[ch] += step[ch]
			while acc[ch] >= 1.0:
				acc[ch] -= 1.0
				pos[ch] += 1
				if pos[ch] >= words[ch] * 2:
					ptr[ch] = lc[ch]
					words[ch] = ln[ch]
					pos[ch] = 0
					intreq |= 0x80 << ch
		out[at + i] = Vector2(clampf(sl * scale, -1.0, 1.0), clampf(sr * scale, -1.0, 1.0))
		if (intreq & intena & 0x780) != 0 and (intena & 0x4000) != 0:
			_irq()
