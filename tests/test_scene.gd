extends SceneTree
## Loads the real start scene, starts level 1 and prints the control sizes (layout debugging).
##   redot --headless --path . --script res://tests/test_scene.gd -- --disks=<folder>

func _initialize() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	print("main size: ", main.size, " children: ", main.get_child_count())
	if main._disks == null:
		print("SKIP: no disks")
		quit(0)
		return
	main._start_level(1)
	for i in 6:
		await process_frame
	var g = main._game
	print("game: ", g, " size=", g.size, " pos=", g.position, " visible=", g.visible)
	for c in g.get_children():
		if c is Control:
			print("  ", c.get_class(), " ", c.name, " size=", c.size, " pos=", c.position, " visible=", c.visible)
		else:
			print("  ", c.get_class(), " ", c.name)
	print("main children order: ", main.get_children().map(func(n): return n.get_class() + ":" + str(n.name)))
	quit(0)
