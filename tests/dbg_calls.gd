extends SceneTree
## Lists every subroutine the original handlers call during a level run (with and without a native hook).
func _initialize() -> void:
	var found := DiskLocator.find()
	var level := 2
	var ticks := 12000
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
	Input.action_press("fire")
	var phases := 0
	for t in ticks:
		g._invuln = 100
		g.py = 20 + (t / 40) % 180
		g._physics_process(0.02)
		if g._finished:
			break
	var keys: Array = g._vm.cpu.call_log.keys()
	keys.sort()
	for k in keys:
		print("%06X  x%d%s" % [k, g._vm.cpu.call_log[k], "  (hook)" if g._vm.hooks.has(k) else ""])
	print("level %d: scroll %.0f locked %s score %d vm instr %d failed %s %s" % [level, g.scroll, str(g.scroll_locked), g.get_score(), g._vm.cpu.instr_count, str(g._vm.cpu.failed), g._vm.cpu.last_error])
	quit(0)
