extends SceneTree
## Headless gameplay smoke test: runs a level for a few thousand ticks with the fire button held.
##   redot --headless --path . --script res://tests/test_sim.gd -- --disks=<folder> [--level=1] [--ticks=3000]

func _initialize() -> void:
	var found := DiskLocator.find()
	if found["disks"] == null:
		print("SKIP: ", found["error"])
		quit(0)
		return
	var level := 1
	var ticks := 3000
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
	Input.action_press("fire")
	Input.action_press("move_down")
	var spawned_max := 0
	for t in ticks:
		g._physics_process(0.02)
		spawned_max = maxi(spawned_max, g._enemies.size())
		if t % 500 == 0:
			print("tick %5d scroll=%7.1f col=%3d enemies=%2d shots=%d bullets=%d score=%d lives=%d" % [
				t, g._scroll, g._col, g._enemies.size(), g._shots.size(), g._bullets.size(), g._score, g._lives])
		if g._finished:
			print("finished at tick ", t, ": ", g._msg.text.replace("\n", " "))
			break
	print("max simultaneous enemies: ", spawned_max, "  final score: ", g._score)
	quit(0)
