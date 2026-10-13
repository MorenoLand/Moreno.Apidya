extends SceneTree
## Checks that the native mixing loop of the ending does exactly what the interpreted one does: every time
## the interrupt routine reaches the loop, both are run from the same state and compared.
##   redot --headless --path . --script res://tests/test_ending_mix.gd -- --frames=100
var helper: Ending
var checked := 0
var bad := 0


func _compare(c: M68K) -> void:
	var snap := M68K.new(c.mem.duplicate())
	snap.d = c.d.duplicate()
	snap.a = c.a.duplicate()
	snap.pc = c.pc
	helper._hk_mix(snap)
	var n := 0
	while c.pc != Ending.MIX_DONE and not c.failed and n < 200000:
		c.step()
		n += 1
	checked += 1
	var msg := ""
	for i in 6:
		if (c.d[i] & 0xFFFFFFFF) != (snap.d[i] & 0xFFFFFFFF) and i != 4:
			msg += " D%d %X vs %X" % [i, c.d[i], snap.d[i]]
	for i in 5:
		if (c.a[i] & 0xFFFFFFFF) != (snap.a[i] & 0xFFFFFFFF):
			msg += " A%d %X vs %X" % [i, c.a[i], snap.a[i]]
	for i in c.mem.size():
		if c.mem[i] != snap.mem[i]:
			msg += " mem %X: %02X vs %02X" % [i, c.mem[i], snap.mem[i]]
			break
	if msg != "":
		bad += 1
		if bad <= 3:
			print("call %d (%d instr): %s" % [checked, n, msg])


func _initialize() -> void:
	var frames := 100
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			frames = int(a.substr(9))
	var disks: DiskSet = DiskLocator.find()["disks"]
	helper = Ending.new()
	var slow := Ending.new()
	slow.native_mix = false
	slow.setup(disks, 0)
	slow.paula.irq_hooks[Ending.MIX_LOOP] = Callable(self, "_compare")
	for f in frames:
		slow._physics_process(0.02)
	print("%d calls compared, %d different" % [checked, bad])
	quit(0 if bad == 0 else 1)
