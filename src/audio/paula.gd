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


## Routines inside an audio interrupt that are answered natively (pc -> Callable(cpu), the hook must leave
## the PC where the original code would have gone on).
var irq_hooks := {}


func _irq() -> void:
	var vec := cpu.r32(0x70)
	if vec == 0:
		return
	if irq_hooks.is_empty():
		cpu.call_sub(vec, 20000, true)
		return
	cpu._push32(M68K.SENTINEL)
	cpu.a[7] = (cpu.a[7] - 2) & 0xFFFFFFFF
	cpu.w16(cpu.a[7], cpu.get_sr())
	cpu.pc = vec
	var n := 0
	while cpu.pc != M68K.SENTINEL and not cpu.failed and n < 40000:
		if irq_hooks.has(cpu.pc):
			irq_hooks[cpu.pc].call(cpu)
		else:
			cpu.step()
		n += 1


## Renders `n` stereo samples (channels 0/3 left, 1/2 right) into `out` starting at `at`.
## The four channels are written out one by one with local variables: this loop is the hot spot of the
## music and sound effects, which run it 50 times a second.
func render(n: int, out: PackedVector2Array, at: int) -> void:
	var mem := cpu.mem
	var msize := mem.size()
	var scale := 1.0 / 16384.0
	var on0 := on[0]
	var vol0 := vol[0]
	var stp0 := step[0]
	var acc0 := acc[0]
	var pos0 := pos[0]
	var ptr0 := ptr[0]
	var end0 := words[0] * 2
	var on1 := on[1]
	var vol1 := vol[1]
	var stp1 := step[1]
	var acc1 := acc[1]
	var pos1 := pos[1]
	var ptr1 := ptr[1]
	var end1 := words[1] * 2
	var on2 := on[2]
	var vol2 := vol[2]
	var stp2 := step[2]
	var acc2 := acc[2]
	var pos2 := pos[2]
	var ptr2 := ptr[2]
	var end2 := words[2] * 2
	var on3 := on[3]
	var vol3 := vol[3]
	var stp3 := step[3]
	var acc3 := acc[3]
	var pos3 := pos[3]
	var ptr3 := ptr[3]
	var end3 := words[3] * 2
	for i in n:
		var sl := 0
		var sr := 0
		if on0 != 0:
			var ad0 := ptr0 + pos0
			if ad0 < msize:
				var s0 := mem[ad0]
				if s0 > 127:
					s0 -= 256
				sl += s0 * vol0
			acc0 += stp0
			while acc0 >= 1.0:
				acc0 -= 1.0
				pos0 += 1
				if pos0 >= end0:
					ptr0 = lc[0]
					end0 = ln[0] * 2
					pos0 = 0
					intreq |= 0x80
		if on1 != 0:
			var ad1 := ptr1 + pos1
			if ad1 < msize:
				var s1 := mem[ad1]
				if s1 > 127:
					s1 -= 256
				sr += s1 * vol1
			acc1 += stp1
			while acc1 >= 1.0:
				acc1 -= 1.0
				pos1 += 1
				if pos1 >= end1:
					ptr1 = lc[1]
					end1 = ln[1] * 2
					pos1 = 0
					intreq |= 0x100
		if on2 != 0:
			var ad2 := ptr2 + pos2
			if ad2 < msize:
				var s2 := mem[ad2]
				if s2 > 127:
					s2 -= 256
				sr += s2 * vol2
			acc2 += stp2
			while acc2 >= 1.0:
				acc2 -= 1.0
				pos2 += 1
				if pos2 >= end2:
					ptr2 = lc[2]
					end2 = ln[2] * 2
					pos2 = 0
					intreq |= 0x200
		if on3 != 0:
			var ad3 := ptr3 + pos3
			if ad3 < msize:
				var s3 := mem[ad3]
				if s3 > 127:
					s3 -= 256
				sl += s3 * vol3
			acc3 += stp3
			while acc3 >= 1.0:
				acc3 -= 1.0
				pos3 += 1
				if pos3 >= end3:
					ptr3 = lc[3]
					end3 = ln[3] * 2
					pos3 = 0
					intreq |= 0x400
		out[at + i] = Vector2(clampf(sl * scale, -1.0, 1.0), clampf(sr * scale, -1.0, 1.0))
		if intreq != 0 and (intreq & intena & 0x780) != 0 and (intena & 0x4000) != 0:
			# the interrupt routine may reprogram the channels: hand the state over and take it back
			acc[0] = acc0
			pos[0] = pos0
			ptr[0] = ptr0
			words[0] = end0 >> 1
			acc[1] = acc1
			pos[1] = pos1
			ptr[1] = ptr1
			words[1] = end1 >> 1
			acc[2] = acc2
			pos[2] = pos2
			ptr[2] = ptr2
			words[2] = end2 >> 1
			acc[3] = acc3
			pos[3] = pos3
			ptr[3] = ptr3
			words[3] = end3 >> 1
			_irq()
			on0 = on[0]
			vol0 = vol[0]
			stp0 = step[0]
			acc0 = acc[0]
			pos0 = pos[0]
			ptr0 = ptr[0]
			end0 = words[0] * 2
			on1 = on[1]
			vol1 = vol[1]
			stp1 = step[1]
			acc1 = acc[1]
			pos1 = pos[1]
			ptr1 = ptr[1]
			end1 = words[1] * 2
			on2 = on[2]
			vol2 = vol[2]
			stp2 = step[2]
			acc2 = acc[2]
			pos2 = pos[2]
			ptr2 = ptr[2]
			end2 = words[2] * 2
			on3 = on[3]
			vol3 = vol[3]
			stp3 = step[3]
			acc3 = acc[3]
			pos3 = pos[3]
			ptr3 = ptr[3]
			end3 = words[3] * 2
	acc[0] = acc0
	pos[0] = pos0
	ptr[0] = ptr0
	words[0] = end0 >> 1
	acc[1] = acc1
	pos[1] = pos1
	ptr[1] = ptr1
	words[1] = end1 >> 1
	acc[2] = acc2
	pos[2] = pos2
	ptr[2] = ptr2
	words[2] = end2 >> 1
	acc[3] = acc3
	pos[3] = pos3
	ptr[3] = ptr3
	words[3] = end3 >> 1
