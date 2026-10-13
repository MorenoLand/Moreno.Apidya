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
	var spawned_max := 0
	var god := false
	var chase := false
	var maxed := false
	for a in OS.get_cmdline_user_args():
		if a == "--god":
			god = true
		elif a == "--chase":
			chase = true
		elif a == "--max":
			maxed = true
	if maxed:
		g._ps.weapon = 3
		g._ps.w1 = 2
		g._ps.w2 = 3
		g._ps.w3 = 3
		g._ps.pods = -1
		g._ps.speed = 3
		g._ps.bomb = 1
	var pickups := 0
	var last_bar := 0
	var py_dir := 1
	for t in ticks:
		if god:
			g._invuln = 100
		# sweep up and down to hit things
		if g.py > 200:
			py_dir = -1
		elif g.py < 20:
			py_dir = 1
		if chase:
			# line up with the nearest enemy ahead (its hit box centre), a few pixels of sweep so that parts get hit
			var target: Enemy = null
			for e in g._enemies:
				if e.dead or e.x < g.px or e.x > 330 or e.hit_h <= 0:
					continue
				if target == null or e.x < target.x:
					target = e
			if target != null:
				var ty := int(target.y) + target.hit_h / 2 - 8 + (t / 6) % 15 - 7
				g.py = clampi(g.py + clampi(ty - g.py, -4, 4), 3, 212)
			else:
				g.py = clampi(g.py + py_dir * 3, 3, 212)
		else:
			Input.action_release("move_up")
			Input.action_release("move_down")
			Input.action_press("move_down" if py_dir > 0 else "move_up")
		g._physics_process(0.02)
		if g._ps.bar != last_bar and g._ps.bar != 0:
			pickups += 1
		last_bar = g._ps.bar
		spawned_max = maxi(spawned_max, g._enemies.size())
		if t % 500 == 0:
			print("tick %5d scroll=%7.1f col=%3d enemies=%2d shots=%d bullets=%d items=%d bar=%d score=%d lives=%d" % [
				t, g.scroll, g._col, g._enemies.size(), g._weapons.shots.size(), g._bullets.size(), g._items.size(),
				g._ps.bar, g._score, g._lives])
		if g._finished:
			print("finished at tick ", t, ": ", g._msg.text.replace("\n", " "))
			break
	print("max simultaneous enemies: ", spawned_max, "  final score: ", g._score, "  meter pickups: ", pickups,
		"  weapon=", g._ps.weapon, " w1=", g._ps.w1, " w2=", g._ps.w2, " w3=", g._ps.w3, " speed=", g._ps.speed, " pods=", g._ps.pods)
	quit(0)
