extends SceneTree
## Investigation tool: boots level 5's own code in the interpreter (blitter performed) and saves the
## playfield buffers as pictures.
##   redot --headless --path . --script res://tests/dbg_l5.gd -- [--steps=200] [--out=prefix]

const BASE := 0xA00
var cpu: M68K
var chip: Chipset
var hooks := {}
var stops := {}


func _hk_rts(c: M68K) -> void:
	c.rts()


func _initialize() -> void:
	var found := DiskLocator.find()
	var steps := 200
	var out := "l5"
	var frames := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--steps="):
			steps = int(a.substr(8))
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--frames="):
			frames = int(a.substr(9))
	var disks: DiskSet = found["disks"]
	var raw := disks.get_data(LevelDefs.LEVELS[5]["file"])
	var mem := PackedByteArray()
	mem.resize(0x80000)
	for i in raw.size():
		mem[BASE + i] = raw[i]
	cpu = M68K.new(mem)
	chip = Chipset.new()
	chip.cpu = cpu
	cpu.io = chip
	cpu.a[7] = 0x7FFE0
	cpu.set_sr(0x2000)
	cpu.a[5] = 0xDFF000
	for a in range(0x4DE00, 0x4DE80, 2):
		hooks[a] = Callable(self, "_hk_rts")
	var sym := VmSymbols.get_symbols(5)
	hooks[sym["sfx"]] = Callable(self, "_hk_rts")
	hooks[sym["music"]] = Callable(self, "_hk_rts")
	stops[0xAB0] = true
	var stopped := cpu.call_hooked(0xA00, hooks, stops, 20000000)
	print("init stopped at %X failed %s %s instr %d blits %d" % [stopped, str(cpu.failed), cpu.last_error, cpu.instr_count, chip.blit_count])
	_dump_vars()
	_save(out + "_init")
	cpu.failed = false
	for i in steps:
		_step()
		if i % 40 == 0:
			print("step %d: ab8=%X abc=%X ac4=%X c8=%X cc=%X" % [i, cpu.r32(0x7AB8), cpu.r32(0x7ABC), cpu.r32(0x7AC4), cpu.r16(0x7AC8), cpu.r16(0x7ACC)])
		if cpu.failed:
			print("step %d failed at %X: %s" % [i, cpu.pc, cpu.last_error])
			break
	_dump_vars()
	var diff := 0
	var first := -1
	for i in range(0xE600, 0x11C68):
		if cpu.mem[i] != raw[i - BASE]:
			diff += 1
			if first < 0:
				first = i
	print("map region changed bytes: %d first %X" % [diff, first])
	var changed := 0
	for i in range(BASE, BASE + raw.size()):
		if cpu.mem[i] != raw[i - BASE]:
			changed += 1
	print("file image changed bytes: %d" % changed)
	_save(out + "_steps")
	quit(0)


func _step() -> void:
	cpu.a[5] = 0xDFF000
	cpu.call_hooked(0x0D40, hooks, {}, 200000)


func _dump_vars() -> void:
	var line := ""
	for a in [0x7AB8, 0x7ABC, 0x7AC0, 0x7AC4, 0x7BB4, 0x7BB8]:
		line += " %X=%X" % [a, cpu.r32(a)]
	for a in [0x7A7C, 0x7A8C, 0x7AC8, 0x7ACA, 0x7ACC, 0x7ABA, 0x7ABE]:
		line += " %X=%X" % [a, cpu.r16(a)]
	print(line)


func _save(prefix: String) -> void:
	var pal: Array = []
	for i in 16:
		var v := cpu.r16(0x89B8 + i * 2)
		pal.append(Color8(((v >> 8) & 15) * 17, ((v >> 4) & 15) * 17, (v & 15) * 17))
	for buf in [0x50000, 0x60000, 0x70000]:
		var img := Image.create(368, 256, false, Image.FORMAT_RGB8)
		for y in 256:
			for xw in 23:
				var words := []
				for p in 4:
					words.append(cpu.r16(buf + y * 184 + p * 46 + xw * 2))
				for b in 16:
					var idx := 0
					for p in 4:
						idx |= ((words[p] >> (15 - b)) & 1) << p
					img.set_pixel(xw * 16 + b, y, pal[idx])
		img.save_png("G:/Development/Working/Amiga/analysis/renders/%s_%X.png" % [prefix, buf])
