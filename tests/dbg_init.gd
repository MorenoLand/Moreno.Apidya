extends SceneTree
## Investigation: runs a level's own start-up code up to its main loop and prints the column counter.
##   redot --headless --path . --script res://tests/dbg_init.gd -- --level=1

const BASE := 0xA00
const COUNTER := {1: 0x7BAA, 2: 0x7A68, 3: 0x7ED0, 4: 0x7D80, 5: 0x7ACC}
var cpu: M68K
var hooks := {}


func _hk_rts(c: M68K) -> void:
	c.rts()


func _initialize() -> void:
	var level := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			level = int(a.substr(8))
	var found := DiskLocator.find()
	var disks: DiskSet = found["disks"]
	var raw := disks.get_data(LevelDefs.LEVELS[level]["file"])
	var mem := PackedByteArray()
	mem.resize(0x80000)
	for i in raw.size():
		mem[BASE + i] = raw[i]
	var label := -1
	for i in range(0, 0x600, 2):
		if raw[i] == 0x20 and raw[i + 1] == 0x39 and raw[i + 2] == 0 and raw[i + 3] == 0xDF and raw[i + 4] == 0xF0 \
				and raw[i + 5] == 4 and raw[i + 6] == 2 and raw[i + 7] == 0x80:
			label = BASE + i
			break
	cpu = M68K.new(mem)
	var chip := Chipset.new()
	chip.cpu = cpu
	chip.perform_blits = false
	cpu.io = chip
	cpu.a[7] = 0x7FFE0
	cpu.set_sr(0x2000)
	cpu.a[5] = 0xDFF000
	for a in range(0x4DE00, 0x4DE80, 2):
		hooks[a] = Callable(self, "_hk_rts")
	var sym := VmSymbols.get_symbols(level)
	hooks[sym["sfx"]] = Callable(self, "_hk_rts")
	hooks[sym["music"]] = Callable(self, "_hk_rts")
	var stopped := cpu.call_hooked(0xA00, hooks, {label: true}, 30000000)
	print("level %d: label %X stopped %X failed %s %s instr %d" % [level, label, stopped, str(cpu.failed), cpu.last_error, cpu.instr_count])
	print("counter var %X = %d" % [COUNTER[level], cpu.r16(COUNTER[level])])
	quit(0)
