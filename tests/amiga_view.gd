extends SceneTree
## Reference viewer: boots a level's own code in the interpreter (blitter performed), runs frames of its
## main loop and saves the picture the original would show.
##   redot --path . --script res://tests/amiga_view.gd -- --level=1 --frames=200 --out=name
##   (needs the window: image saving only, run without --headless is not required)

const BASE := 0xA00
var cpu: M68K
var chip: Chipset
var hooks := {}


func _hk_rts(c: M68K) -> void:
	c.rts()


func _initialize() -> void:
	var level := 1
	var frames := 100
	var out := "view"
	var every := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			level = int(a.substr(8))
		elif a.begins_with("--frames="):
			frames = int(a.substr(9))
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--every="):
			every = int(a.substr(8))
	var found := DiskLocator.find()
	var disks: DiskSet = found["disks"]
	var raw := disks.get_data(LevelDefs.LEVELS[level]["file"])
	var mem := PackedByteArray()
	mem.resize(0x80000)
	for i in raw.size():
		mem[BASE + i] = raw[i]
	# the front end's file stays in memory at $40000 while a level runs: its font strip ($FE90) is the HUD font
	var front := disks.get_data(0)
	for i in mini(front.size(), 0x3F5F0):
		mem[0x40A10 + i] = front[i]
	var label := -1
	for i in range(0, 0x600, 2):
		if raw[i] == 0x20 and raw[i + 1] == 0x39 and raw[i + 2] == 0 and raw[i + 3] == 0xDF and raw[i + 4] == 0xF0 \
				and raw[i + 5] == 4 and raw[i + 6] == 2 and raw[i + 7] == 0x80:
			label = BASE + i
			break
	cpu = M68K.new(mem)
	chip = Chipset.new()
	chip.cpu = cpu
	cpu.io = chip
	cpu.a[7] = 0x7FFE0
	cpu.set_sr(0x2000)
	cpu.a[5] = 0xDFF000
	for a in range(0x4DE00, 0x4DE80, 2):
		hooks[a] = Callable(self, "_hk_rts")
	var sym := VmSymbols.get_symbols(level)
	hooks[sym["sfx"]] = Callable(self, "_hk_rts")
	hooks[sym["music"]] = Callable(self, "_hk_rts")
	var stopped := cpu.call_hooked(0xA00, hooks, {label: true}, 40000000)
	print("level %d: init stopped at %X (label %X) failed %s %s" % [level, stopped, label, str(cpu.failed), cpu.last_error])
	var disp := AmigaDisplay.new()
	disp.mem = cpu.mem
	for f in frames:
		cpu.a[5] = 0xDFF000
		cpu.pc = label
		cpu.step()
		cpu.call_hooked(cpu.pc, hooks, {label: true}, 6000000)
		if cpu.failed:
			print("frame %d failed at %X: %s" % [f, cpu.pc, cpu.last_error])
			break
		if every > 0 and f % every == 0:
			_save(disp, "%s_%04d" % [out, f])
	_save(disp, out)
	quit(0)


func _save(disp: AmigaDisplay, name: String) -> void:
	var cop := ((int(chip.regs.get(0x80, 0)) & 0xFFFF) << 16) | (int(chip.regs.get(0x82, 0)) & 0xFFFE)
	var img := disp.render(cop, chip.regs)
	img.save_png("G:/Development/Working/Amiga/analysis/renders/%s.png" % name)
	var top := img.get_region(Rect2i(0, 36, 640, 20))
	top.resize(1280, 80, Image.INTERPOLATE_NEAREST)
	top.save_png("G:/Development/Working/Amiga/analysis/renders/%s_top.png" % name)
	var bottom := img.get_region(Rect2i(0, 282, 640, 30))
	bottom.resize(1280, 60, Image.INTERPOLATE_NEAREST)
	bottom.save_png("G:/Development/Working/Amiga/analysis/renders/%s_bottom.png" % name)
	print("saved %s (copper %X)" % [name, cop])
