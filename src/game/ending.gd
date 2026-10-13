class_name Ending
extends Control
## The end of the game. The original's own ending program (file 20 of the disk, unpacked at $0A00) is run
## in the 68000 interpreter, frame by frame: its vertical blank routine is entered once per 50 Hz tick, the
## blitter is performed, and its Copper list is drawn by AmigaDisplay. Its music is the TFMX replayer that
## is part of the same file, rendered through the Paula model.
##
## `mode` is what the original's driver passes in D0: 0 normal ending (level 5 done), 1 after level 5 on the
## hardest difficulty, 2 after level 4 on the easy difficulty.

signal finished

const FILE := 20
const LOAD_AT := 0xA00
const PANEL_FILE := 1
const PANEL_AT := 0x4B200
const SPIN_PC := 0xB10          # the main loop waits here for the next frame
const FRAME_FLAG := 0x2212      # set by the vertical blank routine at the end of every frame
const TICK := 0x5024            # replayer tick
const STACK := 0x7E800
const CROP := Rect2i(0, 44, 640, 256)
const RATE := 44100
const SAMPLES := 882
const MAX_INSTR := 600000

# The ending's music is mixed by software: an audio interrupt routine adds up four voices through a volume
# table into a buffer that the hardware plays. Its inner loop (about 25 instructions per output byte, hundreds
# of bytes per frame) is performed natively here, exactly as the loop of $6EBA..$6F26 computes it.
const MIX_LOOP := 0x6EBA
const MIX_DONE := 0x6E6A
# The routine patches its own PC-relative displacements, so the tables are found through the instructions'
# extension words as they are in memory when the loop is entered.
const MIX_LEA := [0x6EC2, 0x6ECE, 0x6EDC, 0x6EEA]     # lea table,SP of each voice
const MIX_OUT_EXT := 0x6EF6                             # move.b (table,PC,D4.w),(A4)+
const MIX_RELOAD_PTR := [0x6E9E, 0x6EA8, 0x6EB2, 0x6F1C]   # movea.l loop_end,An
const MIX_RELOAD_LEN := [0x6EA2, 0x6EAC, 0x6EB6, 0x6F20]   # sub.w loop_length,Dn

## Forwards the custom chip registers to the chipset model (display, blitter) and the audio ones to Paula.
class Bus extends RefCounted:
	var chip: Chipset
	var paula: Paula

	func io_read(addr: int, size: int) -> int:
		return chip.io_read(addr, size)

	func io_write(addr: int, size: int, value: int) -> void:
		chip.io_write(addr, size, value)
		paula.io_write(addr, size, value)

var cpu: M68K
var chip: Chipset
var paula: Paula
var ok := false
var native_mix := true
var mix_calls := 0

var _mode := 0
var _display := AmigaDisplay.new()
var _tex: ImageTexture
var _rect: TextureRect
var _arc: AspectRatioContainer
var _last_hash := 0
var _playback: AudioStreamGeneratorPlayback
var _asp: AudioStreamPlayer
var _out := PackedVector2Array()
var _done := false
var _frames := 0
var _hooks := {}


func setup(disks: DiskSet, mode: int) -> void:
	_mode = mode
	var mem := PackedByteArray()
	mem.resize(0x80000)
	var panel := disks.get_data(PANEL_FILE)
	for i in panel.size():
		mem[PANEL_AT + i] = panel[i]
	var raw := disks.get_data(FILE)
	if raw.is_empty():
		return
	for i in mini(raw.size(), mem.size() - LOAD_AT):
		mem[LOAD_AT + i] = raw[i]
	cpu = M68K.new(mem)
	chip = Chipset.new()
	chip.cpu = cpu
	paula = Paula.new()
	paula.cpu = cpu
	paula.set_rate(float(RATE))
	var bus := Bus.new()
	bus.chip = chip
	bus.paula = paula
	cpu.io = bus
	cpu.a[7] = STACK
	cpu.set_sr(0x2000)
	cpu.a[5] = 0xDFF000
	cpu.d[0] = mode
	for a in range(0x7F000, 0x7F020, 2):
		_hooks[a] = Callable(self, "_hk_rts")
	if native_mix:
		paula.irq_hooks[MIX_LOOP] = Callable(self, "_hk_mix")
		_hooks[MIX_LOOP] = Callable(self, "_hk_mix")
	cpu._push32(M68K.SENTINEL)
	cpu.pc = LOAD_AT
	_display.mem = cpu.mem
	_out.resize(SAMPLES)
	ok = true


func _hk_rts(c: M68K) -> void:
	c.rts()


## The voice mixing loop: D0..D3 are the voices' positions (high word = fraction, low word = negative offset
## from the sample's end), A0..A3 the ends of the samples, D6 D7 A5 A6 the steps, A4 the output, D5.w the
## count. Ends with the registers the original leaves and the PC at its exit.
func _hk_mix(c: M68K) -> void:
	mix_calls += 1
	var mem := c.mem
	var tb0 := _pcrel(c, MIX_LEA[0])
	var tb1 := _pcrel(c, MIX_LEA[1])
	var tb2 := _pcrel(c, MIX_LEA[2])
	var tb3 := _pcrel(c, MIX_LEA[3])
	var out_tb := MIX_OUT_EXT + M68K.sx(c.r16(MIX_OUT_EXT) & 0xFF, 0)
	var rp0 := _pcrel(c, MIX_RELOAD_PTR[0])
	var rp1 := _pcrel(c, MIX_RELOAD_PTR[1])
	var rp2 := _pcrel(c, MIX_RELOAD_PTR[2])
	var rp3 := _pcrel(c, MIX_RELOAD_PTR[3])
	var rl0 := _pcrel(c, MIX_RELOAD_LEN[0])
	var rl1 := _pcrel(c, MIX_RELOAD_LEN[1])
	var rl2 := _pcrel(c, MIX_RELOAD_LEN[2])
	var rl3 := _pcrel(c, MIX_RELOAD_LEN[3])
	var d0 := c.d[0]
	var d1 := c.d[1]
	var d2 := c.d[2]
	var d3 := c.d[3]
	var a0 := c.a[0]
	var a1 := c.a[1]
	var a2 := c.a[2]
	var a3 := c.a[3]
	var st0 := c.d[6]
	var st1 := c.d[7]
	var st2 := c.a[5]
	var st3 := c.a[6]
	var op := c.a[4]
	var cnt := c.d[5] & 0xFFFF
	var t3 := 0
	while true:
		var i0 := d0 & 0xFFFF
		var i1 := d1 & 0xFFFF
		var i2 := d2 & 0xFFFF
		var i3 := d3 & 0xFFFF
		if i0 >= 0x8000:
			i0 -= 0x10000
		if i1 >= 0x8000:
			i1 -= 0x10000
		if i2 >= 0x8000:
			i2 -= 0x10000
		if i3 >= 0x8000:
			i3 -= 0x10000
		var sum := mem[(tb0 + mem[(a0 + i0) & 0x7FFFF]) & 0x7FFFF] + mem[(tb1 + mem[(a1 + i1) & 0x7FFFF]) & 0x7FFFF]
		sum += mem[(tb2 + mem[(a2 + i2) & 0x7FFFF]) & 0x7FFFF]
		t3 = mem[(tb3 + mem[(a3 + i3) & 0x7FFFF]) & 0x7FFFF]
		sum += t3
		mem[op & 0x7FFFF] = mem[(out_tb + (sum & 0xFFFF)) & 0x7FFFF]
		op += 1
		var n0 := d0 + st0
		var low := ((n0 & 0xFFFF) + ((n0 >> 32) & 1)) & 0xFFFF
		d0 = (n0 & 0xFFFF0000) | low
		if (low & 0x8000) == 0:
			a0 = c.r32(rp0)
			low = (low - c.r16(rl0)) & 0xFFFF
			d0 = (d0 & 0xFFFF0000) | low
		var n1 := d1 + st1
		low = ((n1 & 0xFFFF) + ((n1 >> 32) & 1)) & 0xFFFF
		d1 = (n1 & 0xFFFF0000) | low
		if (low & 0x8000) == 0:
			a1 = c.r32(rp1)
			low = (low - c.r16(rl1)) & 0xFFFF
			d1 = (d1 & 0xFFFF0000) | low
		var n2 := d2 + st2
		low = ((n2 & 0xFFFF) + ((n2 >> 32) & 1)) & 0xFFFF
		d2 = (n2 & 0xFFFF0000) | low
		if (low & 0x8000) == 0:
			a2 = c.r32(rp2)
			low = (low - c.r16(rl2)) & 0xFFFF
			d2 = (d2 & 0xFFFF0000) | low
		var n3 := d3 + st3
		low = ((n3 & 0xFFFF) + ((n3 >> 32) & 1)) & 0xFFFF
		d3 = (n3 & 0xFFFF0000) | low
		if (low & 0x8000) == 0:
			a3 = c.r32(rp3)
			low = (low - c.r16(rl3)) & 0xFFFF
			d3 = (d3 & 0xFFFF0000) | low
		cnt = (cnt - 1) & 0xFFFF
		if cnt == 0xFFFF:
			break
	c.d[0] = d0 & 0xFFFFFFFF
	c.d[1] = d1 & 0xFFFFFFFF
	c.d[2] = d2 & 0xFFFFFFFF
	c.d[3] = d3 & 0xFFFFFFFF
	c.a[0] = a0
	c.a[1] = a1
	c.a[2] = a2
	c.a[3] = a3
	c.a[4] = op & 0xFFFFFFFF
	c.d[4] = 0
	c.d[5] = (t3 << 16) | 0xFFFF
	c.a[7] = tb3
	c.pc = MIX_DONE


## Address a PC-relative operand points at: the extension word's own address plus its 16 bit displacement.
static func _pcrel(c: M68K, ext_addr: int) -> int:
	var d := c.r16(ext_addr)
	if d >= 0x8000:
		d -= 0x10000
	return (ext_addr + d) & 0x7FFFF


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.color = Color.BLACK
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	_arc = AspectRatioContainer.new()
	_arc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_arc.ratio = 4.0 / 3.0
	add_child(_arc)
	_rect = TextureRect.new()
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_arc.add_child(_rect)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.25
	_asp = AudioStreamPlayer.new()
	_asp.stream = gen
	add_child(_asp)
	_asp.play()
	_playback = _asp.get_stream_playback() as AudioStreamGeneratorPlayback
	if not ok:
		finished.emit.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			_end()


func _end() -> void:
	if _done:
		return
	_done = true
	if _asp != null:
		_asp.stop()
	finished.emit()


func _physics_process(_delta: float) -> void:
	if _done or not ok:
		return
	_frames += 1
	var n := 0
	while cpu.pc != M68K.SENTINEL and not cpu.failed and n < MAX_INSTR:
		var pc := cpu.pc
		if pc == SPIN_PC and cpu.mem[FRAME_FLAG] == 0:
			break
		if _hooks.has(pc):
			_hooks[pc].call(cpu)
		elif ((cpu.mem[pc] << 8) | cpu.mem[pc + 1]) == 0x4E40:
			cpu.pc += 2                  # TRAP #0 of the driver: only moves the supervisor stack
			cpu.a[7] = 0x4C87A
		else:
			cpu.step()
		n += 1
	if cpu.failed or cpu.pc == M68K.SENTINEL:
		_end()
		return
	# the vertical blank interrupt, then the music replayer's tick (call_sub leaves the PC at its sentinel)
	var saved := cpu.pc
	var vec := cpu.r32(0x74)
	if vec != 0:
		cpu.call_sub(vec, MAX_INSTR, true)
		cpu.pc = saved
	cpu.call_sub(TICK, MAX_INSTR)
	cpu.pc = saved
	if cpu.failed:
		_end()
		return
	paula.render(SAMPLES, _out, 0)     # may enter an audio interrupt, which leaves the PC at its sentinel
	cpu.pc = saved
	if _playback != null and _playback.get_frames_available() >= SAMPLES:
		_playback.push_buffer(_out)


## The picture is only redrawn when something it is made of has changed.
func _process(_delta: float) -> void:
	if _done or not ok:
		return
	var cop := ((int(chip.regs.get(0x80, 0)) & 0xFFFF) << 16) | (int(chip.regs.get(0x82, 0)) & 0xFFFE)
	if cop == 0:
		return
	var h: int = hash(chip.regs)
	for r in _display.watch_ranges(cop, chip.regs):
		h = h * 31 + hash(cpu.mem.slice(r.x, r.y))
	if h == _last_hash and _tex != null:
		return
	_last_hash = h
	var img := _display.render(cop, chip.regs).get_region(CROP)
	if _tex == null:
		_tex = ImageTexture.create_from_image(img)
		_rect.texture = _tex
	else:
		_tex.update(img)
