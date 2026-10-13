extends SceneTree
## Developer tool: starts a level with the real renderer, advances it and saves a screenshot.
##   redot --path . --script res://tests/shot.gd -- --disks=<folder> --out=<file.png> [--level=1] [--ticks=600] [--wide]

func _initialize() -> void:
	var found := DiskLocator.find()
	if found["disks"] == null:
		print("SKIP: ", found["error"])
		quit(0)
		return
	var level := 1
	var ticks := 600
	var out := "screenshot.png"
	var wide := false
	var god := false
	var bomb := 0
	var pulse := 0
	var start_col := -1
	var ps_arg: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			level = int(a.substr(8))
		elif a.begins_with("--ticks="):
			ticks = int(a.substr(8))
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--wide":
			wide = true
		elif a == "--god":
			god = true
		elif a.begins_with("--col="):
			start_col = int(a.substr(6))
		elif a.begins_with("--bomb="):
			bomb = int(a.substr(7))
		elif a.begins_with("--pulse="):
			pulse = int(a.substr(8))
		elif a.begins_with("--ps="):
			ps_arg = a.substr(5).split(",")
	var g := Game.new()
	g.setup(found["disks"], level)
	root.add_child(g)
	await process_frame
	await process_frame
	g._set_widescreen(wide, false)
	if ps_arg.size() >= 6:
		g._ps.weapon = int(ps_arg[0])
		g._ps.w1 = int(ps_arg[1])
		g._ps.w2 = int(ps_arg[2])
		g._ps.w3 = int(ps_arg[3])
		g._ps.pods = int(ps_arg[4])
		g._ps.speed = int(ps_arg[5])
	g._ps.bomb = bomb
	if start_col >= 0:
		g.jump_to_col(start_col)
	Input.action_press("fire")
	for t in ticks:
		if god:
			g._invuln = 100
		if pulse > 0:
			if (t / pulse) % 2 == 0:
				Input.action_press("fire")
			else:
				Input.action_release("fire")
		g._physics_process(0.02)
	for i in 5:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("saved ", out, " ", img.get_size())
	quit(0)
