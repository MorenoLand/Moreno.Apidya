class_name Chipset
extends RefCounted
## The custom chip registers as far as the game's own code needs them when it is run by the interpreter:
## the blitter is performed on write to BLTSIZE, the beam position moves, nothing is ever busy.
## Plug an instance into M68K.io.

var cpu: M68K
var regs := {}                   # register offset -> last word written
var blit_count := 0
var perform_blits := true
var beam := 0x10000              # VPOSR/VHPOSR as one long, advances on every read
var rng := RandomNumberGenerator.new()
var on_blit := Callable()        # optional: called with the register file before the blit is performed


func io_read(addr: int, size: int) -> int:
	if addr >= 0xBFD000 and addr < 0xC00000:
		return 0xFF                                  # CIA: no key, fire button released, no drive
	var a := addr & 0x1FE
	match a:
		0x002:
			return 0                                  # DMACONR: blitter never busy
		0x004:
			beam = (beam + 0x100) & 0x1FF00
			return (beam >> 16) & 0xFFFF
		0x006:
			return beam & 0xFFFF
		0x00A, 0x00C:
			return 0                                  # no joystick movement
		0x01E:
			return 0x7FFF                             # INTREQR: everything pending, nothing waits long
	return 0


func io_write(addr: int, _size: int, value: int) -> void:
	if addr < 0xDFF000 or addr >= 0xE00000:
		return
	var a := addr & 0x1FE
	regs[a] = value & 0xFFFF
	if a == Blitter.SIZE:
		blit_count += 1
		if on_blit.is_valid():
			on_blit.call(regs)
		if perform_blits:
			Blitter.run(cpu.mem, regs)
