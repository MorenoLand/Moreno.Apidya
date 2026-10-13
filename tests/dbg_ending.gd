extends SceneTree
## Developer tool: runs a program file of the disk (default: file 20, the end of the game) from $A00 in the
## interpreter and saves what its Copper list displays after every slice of instructions.
##   redot --path . --script res://tests/dbg_ending.gd -- --file=20 --d0=0 --slices=30 --slice=50   (slice = frames per picture) --out=end
var cpu: M68K
var chip: Chipset
var hooks := {}


func _hk_rts(c: M68K) -> void:
	c.rts()


func _hk_loader(c: M68K) -> void:
	print("   loader call at %X: D0=%d (%X) A0=%X D1=%X D2=%X" % [c.pc, c.d[0], c.d[0], c.a[0], c.d[1], c.d[2]])
	c.rts()


func _initialize() -> void:
	var file := 20
	var d0 := 0
	var slices := 20
	var slice := 1000000
	var out := "end"
	var spin := 0xB10
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--file="):
			file = int(a.substr(7))
		elif a.begins_with("--d0="):
			d0 = int(a.substr(5))
		elif a.begins_with("--slices="):
			slices = int(a.substr(9))
		elif a.begins_with("--slice="):
			slice = int(a.substr(8))
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--spin="):
			spin = a.substr(7).hex_to_int()
	var disks: DiskSet = DiskLocator.find()["disks"]
	var raw := disks.get_data(file)
	print("file %d: %d bytes" % [file, raw.size()])
	var mem := PackedByteArray()
	mem.resize(0x80000)
	var panel := disks.get_data(1)
	for i in panel.size():
		mem[0x4B200 + i] = panel[i]
	for i in raw.size():
		mem[0xA00 + i] = raw[i]
	cpu = M68K.new(mem)
	chip = Chipset.new()
	chip.cpu = cpu
	cpu.io = chip
	cpu.a[7] = 0x7E800
	cpu.set_sr(0x2000)
	cpu.a[5] = 0xDFF000
	cpu.d[0] = d0
	for a in range(0x4DE00, 0x4DE80, 2):
		hooks[a] = Callable(self, "_hk_rts")
	for a in range(0x7F000, 0x7F020, 2):
		hooks[a] = Callable(self, "_hk_loader")
	cpu._push32(M68K.SENTINEL)
	cpu.pc = 0xA00
	var disp := AmigaDisplay.new()
	disp.mem = cpu.mem
	var frame_instr := 30000
	var vec := 0
	for s in slices:
		var n := 0
		var t0 := Time.get_ticks_msec()
		# `slice` frames of 50 Hz: run the main program, then enter the vertical blank interrupt
		for f in slice:
			var k := 0
			while cpu.pc != M68K.SENTINEL and not cpu.failed and k < frame_instr:
				if cpu.pc == spin and cpu.mem[0x2212 + 0] == 0:
					break          # waiting for the next frame: nothing to compute
				if hooks.has(cpu.pc):
					hooks[cpu.pc].call(cpu)
				elif (cpu.mem[cpu.pc] << 8 | cpu.mem[cpu.pc + 1]) == 0x4E40:
					cpu.pc += 2
					cpu.a[7] = 0x4C87A
				else:
					cpu.step()
				k += 1
			n += k
			if cpu.pc == M68K.SENTINEL or cpu.failed:
				break
			vec = cpu.r32(0x74)
			if vec != 0:
				cpu._push32(cpu.pc)
				cpu.a[7] = (cpu.a[7] - 2) & 0xFFFFFFFF
				cpu.w16(cpu.a[7], cpu.get_sr())
				cpu.pc = vec
		print("slice %d: pc=%X instr=%d failed=%s %s  cpu %d ms" % [s, cpu.pc, n, str(cpu.failed), cpu.last_error, Time.get_ticks_msec() - t0])
		var t1 := Time.get_ticks_msec()
		var cop := ((int(chip.regs.get(0x80, 0)) & 0xFFFF) << 16) | (int(chip.regs.get(0x82, 0)) & 0xFFFE)
		if cop != 0:
			var img := disp.render(cop, chip.regs)
			print("   render %d ms" % (Time.get_ticks_msec() - t1))
			img.save_png("G:/Development/Working/Amiga/analysis/renders/%s_%02d.png" % [out, s])
		if cpu.pc == M68K.SENTINEL or cpu.failed:
			break
	print("vectors: lvl1 %X lvl2 %X lvl3 %X lvl4 (70) %X lvl5 (74) %X lvl6 (78) %X; INTENA %X DMACON %X" % [cpu.r32(0x64), cpu.r32(0x68), cpu.r32(0x6C), cpu.r32(0x70), cpu.r32(0x74), cpu.r32(0x78), 0, 0])
	quit(0)
