class_name Blitter
extends RefCounted
## The Amiga blitter: copies and logic operations on 16 bit words (areas, ascending or descending, with
## shifts and masks; no line or fill mode) in a flat chip RAM image. The register file is a dictionary
## keyed by the register offset (BLTCON0 = 0x040 ...), exactly as the CPU wrote it. The pointer registers
## are left where the real hardware leaves them (past the area), because code relies on that.

const CON0 := 0x040
const CON1 := 0x042
const AFWM := 0x044
const ALWM := 0x046
const CPTH := 0x048
const CPTL := 0x04A
const BPTH := 0x04C
const BPTL := 0x04E
const APTH := 0x050
const APTL := 0x052
const DPTH := 0x054
const DPTL := 0x056
const SIZE := 0x058
const CMOD := 0x060
const BMOD := 0x062
const AMOD := 0x064
const DMOD := 0x066
const CDAT := 0x070
const BDAT := 0x072
const ADAT := 0x074


static func _s16(v: int) -> int:
	v &= 0xFFFF
	return v - 65536 if v >= 32768 else v


static func _pt(r: Dictionary, hi: int, lo: int) -> int:
	return ((int(r.get(hi, 0)) & 0xFFFF) << 16) | (int(r.get(lo, 0)) & 0xFFFE)


static func _set_pt(r: Dictionary, hi: int, lo: int, v: int) -> void:
	r[hi] = (v >> 16) & 0xFFFF
	r[lo] = v & 0xFFFE


static func run(mem: PackedByteArray, r: Dictionary) -> void:
	var con0: int = r.get(CON0, 0)
	var con1: int = r.get(CON1, 0)
	if (con1 & 1) != 0:
		return                                         # line mode is not needed by the game
	var size: int = r.get(SIZE, 0)
	var h := size >> 6
	if h == 0:
		h = 1024
	var w := size & 63
	if w == 0:
		w = 64
	var use_a := (con0 & 0x800) != 0
	var use_b := (con0 & 0x400) != 0
	var use_c := (con0 & 0x200) != 0
	var use_d := (con0 & 0x100) != 0
	var ash := con0 >> 12
	var bsh := con1 >> 12
	var lf := con0 & 0xFF
	var desc := (con1 & 2) != 0
	var afwm: int = int(r.get(AFWM, 0xFFFF)) & 0xFFFF
	var alwm: int = int(r.get(ALWM, 0xFFFF)) & 0xFFFF
	var ap := _pt(r, APTH, APTL)
	var bp := _pt(r, BPTH, BPTL)
	var cp := _pt(r, CPTH, CPTL)
	var dp := _pt(r, DPTH, DPTL)
	var amod := _s16(int(r.get(AMOD, 0)))
	var bmod := _s16(int(r.get(BMOD, 0)))
	var cmod := _s16(int(r.get(CMOD, 0)))
	var dmod := _s16(int(r.get(DMOD, 0)))
	var adat: int = int(r.get(ADAT, 0)) & 0xFFFF
	var bdat: int = int(r.get(BDAT, 0)) & 0xFFFF
	var cdat: int = int(r.get(CDAT, 0)) & 0xFFFF
	var mask := mem.size() - 1                          # chip RAM mirrors
	var step := -2 if desc else 2
	for _row in h:
		var prev_a := 0
		var prev_b := 0
		for col in w:
			var aw := adat
			if use_a:
				var o := ap & mask
				aw = (mem[o] << 8) | mem[o + 1]
				ap += step
			if col == 0:
				aw &= alwm if desc else afwm
			if col == w - 1:
				aw &= afwm if desc else alwm
			var bw := bdat
			if use_b:
				var o2 := bp & mask
				bw = (mem[o2] << 8) | mem[o2 + 1]
				bp += step
			var cw := cdat
			if use_c:
				var o3 := cp & mask
				cw = (mem[o3] << 8) | mem[o3 + 1]
				cp += step
			var a_s: int
			var b_s: int
			if desc:
				a_s = ((((aw << 16) | prev_a) << ash) >> 16) & 0xFFFF
				b_s = ((((bw << 16) | prev_b) << bsh) >> 16) & 0xFFFF
			else:
				a_s = (((prev_a << 16) | aw) >> ash) & 0xFFFF
				b_s = (((prev_b << 16) | bw) >> bsh) & 0xFFFF
			prev_a = aw
			prev_b = bw
			var d := 0
			if lf & 0x80:
				d |= a_s & b_s & cw
			if lf & 0x40:
				d |= a_s & b_s & ~cw
			if lf & 0x20:
				d |= a_s & ~b_s & cw
			if lf & 0x10:
				d |= a_s & ~b_s & ~cw
			if lf & 0x08:
				d |= ~a_s & b_s & cw
			if lf & 0x04:
				d |= ~a_s & b_s & ~cw
			if lf & 0x02:
				d |= ~a_s & ~b_s & cw
			if lf & 0x01:
				d |= ~a_s & ~b_s & ~cw
			d &= 0xFFFF
			if use_d:
				var o4 := dp & mask
				mem[o4] = d >> 8
				mem[o4 + 1] = d & 0xFF
				dp += step
		if desc:
			ap -= amod
			bp -= bmod
			cp -= cmod
			dp -= dmod
		else:
			ap += amod
			bp += bmod
			cp += cmod
			dp += dmod
	if use_a:
		_set_pt(r, APTH, APTL, ap)
	if use_b:
		_set_pt(r, BPTH, BPTL, bp)
	if use_c:
		_set_pt(r, CPTH, CPTL, cp)
	if use_d:
		_set_pt(r, DPTH, DPTL, dp)
