extends SceneTree
## Plays the end of a level (from --col) with the autopilot until the ship has left, prints the carried state.
##   redot --headless --path . --script res://tests/dbg_end.gd -- --level=1 --col=440
var _carry := {}
var _done := false


func _on_complete(carry: Dictionary) -> void:
	_carry = carry
	_done = true


func _initialize() -> void:
	var found := DiskLocator.find()
	var level := 1
	var col := 440
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			level = int(a.substr(8))
		elif a.begins_with("--col="):
			col = int(a.substr(6))
	var g := Game.new()
	g.setup(found["disks"], level, {"carry": {"score": 4200, "lives": 2, "next_extra": 20000,
			"ps": {"speed": 3, "weapon": 2, "w1": 1, "w2": 2, "w3": 0, "pods": 1, "bomb": 1, "bar": 0}}})
	g.level_complete.connect(_on_complete)
	root.add_child(g)
	await process_frame
	await process_frame
	print("start: score %d lives %d weapon %d speed %d" % [g._score, g._lives, g._ps.weapon, g._ps.speed])
	g.jump_to_col(col)
	Input.action_press("fire")
	for t in 6000:
		g._invuln = 100
		g.py = 20 + (t / 40) % 180
		for e in g._enemies:
			if e.vm_slot >= 0 and e.x < 330 and e.y < 230:
				g.py = clampi(int(e.y) + e.hit_h / 2 - 12 + (t / 5) % 21, 3, 212)
				break
		g._physics_process(0.02)
		if _done:
			print("level complete at tick %d: %s" % [t, str(_carry)])
			break
	if not _done:
		print("NOT complete, finished=%s" % str(g._finished))
	quit(0)
