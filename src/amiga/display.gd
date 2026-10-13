class_name AmigaDisplay
extends RefCounted
## Reference renderer: runs a Copper list over a chip RAM image (as left behind by the original code run
## in the interpreter) and draws the bitplanes and sprites the way the hardware would. Used by the tests
## to look at what the original's screen contains; the game itself does not use it.

const LINES := 312
const WIDTH := 640

var mem: PackedByteArray
var regs := {}              # custom registers as the copper / CPU left them (0x..E offsets)


func _w(a: int) -> int:
	a &= mem.size() - 1
	return (mem[a] << 8) | mem[a + 1]


static func _rgb(v: int) -> int:
	return (((v >> 8) & 15) * 17) << 16 | (((v >> 4) & 15) * 17) << 8 | ((v & 15) * 17)


## Returns an RGB8 image WIDTH x LINES (lowres pixels doubled).
func render(copper: int, regs_in: Dictionary) -> Image:
	regs = regs_in.duplicate()
	var img := Image.create(WIDTH, LINES, false, Image.FORMAT_RGB8)
	var colors: Array[int] = []
	colors.resize(32)
	for i in 32:
		colors[i] = int(regs.get(0x180 + i * 2, 0)) & 0xFFF
	var bplpt: Array[int] = [0, 0, 0, 0, 0, 0]
	var sprpt: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
	var bplcon0 := int(regs.get(0x100, 0))
	var bplcon1 := int(regs.get(0x102, 0))
	var mod1 := int(regs.get(0x108, 0))
	var mod2 := int(regs.get(0x10A, 0))
	var diwstrt := int(regs.get(0x8E, 0x2C81))
	var diwstop := int(regs.get(0x90, 0x2CC1))
	var ddfstrt := int(regs.get(0x92, 0x38))
	var ddfstop := int(regs.get(0x94, 0xD0))
	var cop := copper
	var wait_line := -1          # copper waiting for this line
	var line_state_ok := true
	var last_v := -1
	var wrap := 0
	for line in LINES:
		# copper instructions due on or before this line
		var guard := 0
		while guard < 400:
			guard += 1
			if wait_line > line:
				break
			var a := _w(cop)
			var b := _w(cop + 2)
			if a == 0xFFFF and b == 0xFFFE:
				wait_line = 100000
				break
			cop += 4
			if a & 1:
				var v := (a >> 8) & 0xFF
				if v < last_v:
					wrap += 256
				last_v = v
				wait_line = v + wrap
				if wait_line <= line:
					wait_line = -1
				continue
			var r := a & 0x1FE
			regs[r] = b
			if r >= 0x180 and r <= 0x1BE:
				colors[(r - 0x180) >> 1] = b & 0xFFF
			elif r >= 0xE0 and r <= 0xF6:
				var k := (r - 0xE0) >> 2
				if r & 2:
					bplpt[k] = (bplpt[k] & 0xFFFF0000) | (b & 0xFFFE)
				else:
					bplpt[k] = (bplpt[k] & 0xFFFF) | ((b & 0x1F) << 16)
			elif r >= 0x120 and r <= 0x13E:
				var k2 := (r - 0x120) >> 2
				if r & 2:
					sprpt[k2] = (sprpt[k2] & 0xFFFF0000) | (b & 0xFFFE)
				else:
					sprpt[k2] = (sprpt[k2] & 0xFFFF) | ((b & 0x1F) << 16)
			elif r == 0x100:
				bplcon0 = b
			elif r == 0x102:
				bplcon1 = b
			elif r == 0x108:
				mod1 = _s16(b)
			elif r == 0x10A:
				mod2 = _s16(b)
			elif r == 0x8E:
				diwstrt = b
			elif r == 0x90:
				diwstop = b
			elif r == 0x92:
				ddfstrt = b
			elif r == 0x94:
				ddfstop = b
		var planes := (bplcon0 >> 12) & 7
		var hires := (bplcon0 & 0x8000) != 0
		var vstart := (diwstrt >> 8) & 0xFF
		var vstop := (diwstop >> 8) & 0xFF
		if vstop < 0x80:
			vstop += 0x100
		var hstart := diwstrt & 0xFF
		var hstop := (diwstop & 0xFF) + 0x100
		if planes > 0 and line >= vstart and line < vstop:
			var nwords := ((ddfstop - ddfstrt) >> (2 if hires else 3)) + (2 if hires else 1)
			var x0 := ddfstrt * 2 + 17 - hstart + (bplcon1 & 15)
			var row: Array[PackedInt32Array] = []
			var data: Array[PackedInt32Array] = []
			for p in planes:
				var words := PackedInt32Array()
				words.resize(nwords)
				for i in nwords:
					words[i] = _w(bplpt[p] + i * 2)
				data.append(words)
				bplpt[p] += nwords * 2 + (mod1 if (p & 1) == 0 else mod2)
			var width_px := hstop - hstart
			for wi in nwords:
				for bit in 16:
					var idx := 0
					for p in planes:
						idx |= ((data[p][wi] >> (15 - bit)) & 1) << p
					var col := _rgb(colors[idx & 31])
					var c := Color8((col >> 16) & 255, (col >> 8) & 255, col & 255)
					if hires:
						var ox := x0 * 2 + wi * 16 + bit
						if ox >= 0 and ox < width_px * 2:
							img.set_pixel(ox, line, c)
					else:
						var lx := x0 + wi * 16 + bit
						if lx >= 0 and lx < width_px:
							img.set_pixel(lx * 2, line, c)
							img.set_pixel(lx * 2 + 1, line, c)
		# sprites (not attached): plain 16 pixel wide, 3 colours
		for sp in 8:
			if sprpt[sp] == 0:
				continue
			var a2 := sprpt[sp]
			var guard2 := 0
			while guard2 < 300:
				guard2 += 1
				var w0 := _w(a2)
				var w1 := _w(a2 + 2)
				if w0 == 0 and w1 == 0:
					break
				var vs := (w0 >> 8) | (0x100 if (w1 & 4) else 0)
				var ve := (w1 >> 8) | (0x100 if (w1 & 2) else 0)
				if line < vs:
					break
				if line >= ve:
					a2 += 4 + (ve - vs) * 4
					continue
				var rowi := line - vs
				var d0 := _w(a2 + 4 + rowi * 4)
				var d1 := _w(a2 + 6 + rowi * 4)
				var hs := ((w0 & 0xFF) << 1) | (w1 & 1)
				for bit in 16:
					var v2 := ((d0 >> (15 - bit)) & 1) | (((d1 >> (15 - bit)) & 1) << 1)
					if v2 == 0:
						continue
					var sx := hs - hstart + bit
					if sx < 0 or sx >= 320:
						continue
					var cc := _rgb(colors[16 + (sp >> 1) * 4 + v2])
					var c2 := Color8((cc >> 16) & 255, (cc >> 8) & 255, cc & 255)
					img.set_pixel(sx * 2, line, c2)
					img.set_pixel(sx * 2 + 1, line, c2)
				break
	return img


static func _s16(v: int) -> int:
	v &= 0xFFFF
	return v - 65536 if v >= 32768 else v
