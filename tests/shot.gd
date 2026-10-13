extends SceneTree
## Developer tool: starts a level with the real renderer, advances it and saves a screenshot.
##   redot --path . --script res://tests/shot.gd -- --disks=<folder> --out=<file.png> [--level=1] [--ticks=600]

func _initialize() -> void:
	var found := DiskLocator.find()
	if found["disks"] == null:
		print("SKIP: ", found["error"])
		quit(0)
		return
	var level := 1
	var ticks := 600
	var out := "screenshot.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			level = int(a.substr(8))
		elif a.begins_with("--ticks="):
			ticks = int(a.substr(8))
		elif a.begins_with("--out="):
			out = a.substr(6)
	var g := Game.new()
	g.setup(found["disks"], level)
	root.add_child(g)
	await process_frame
	await process_frame
	Input.action_press("move_right")
	Input.action_press("fire")
	for t in ticks:
		g._physics_process(0.02)
	for i in 5:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("saved ", out, " ", img.get_size())
	quit(0)
