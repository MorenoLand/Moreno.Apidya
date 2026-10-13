extends SceneTree
## Lists the subroutines the original enemy handlers call that are not replaced by native code.
##   redot --headless --path . --script res://tests/test_vm_calls.gd -- --disks=<folder> --level=1 --ticks=9000
func _initialize() -> void:
	var found := DiskLocator.find()
	if found["disks"] == null:
		print("SKIP: ", found["error"])
		quit(0)
		return
	var level := 1
	var ticks := 9000
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			level = int(a.substr(8))
		elif a.begins_with("--ticks="):
			ticks = int(a.substr(8))
	var g := Game.new()
	g.setup(found["disks"], level)
	root.add_child(g)
	await process_frame
	await process_frame
	g._vm.cpu.trace_calls = true
	g._vm.cpu.call_log = {}
	Input.action_press("fire")
	for t in ticks:
		g._invuln = 100
		g.py = 20 + (t / 40) % 180
		g._physics_process(0.02)
		if g._finished:
			break
	var keys: Array = g._vm.cpu.call_log.keys()
	keys.sort()
	for k in keys:
		var hooked: bool = g._vm.hooks.has(k)
		print("%06X  x%d%s" % [k, g._vm.cpu.call_log[k], "  (hook)" if hooked else ""])
	print("vm instructions: ", g._vm.cpu.instr_count, "  scroll ", g.scroll, " locked ", g.scroll_locked, " score ", g.get_score())
	quit(0)
