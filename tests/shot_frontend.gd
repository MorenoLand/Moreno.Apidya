extends SceneTree
## Developer tool: runs the front end with the real renderer and saves screenshots of its screens.
##   redot --path . --script res://tests/shot_frontend.gd -- --disks=<folder> --out=<prefix> [--wide]
## Writes <prefix>_title.png, _story.png, _options.png, _options2.png, _scores.png

func _initialize() -> void:
	var found := DiskLocator.find()
	if found["disks"] == null:
		print("SKIP: ", found["error"])
		quit(0)
		return
	var out := "fe"
	var wide := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--wide":
			wide = true
	var fe := FrontEnd.new()
	fe.setup(found["disks"])
	root.add_child(fe)
	await process_frame
	await process_frame
	fe._widescreen = wide
	fe._apply_aspect()
	await _run(fe, 120)
	await _save(out + "_title.png")
	# jump into the second scene with a story page visible
	fe._page_t = 0
	fe._page_on = false
	fe._page = 0
	fe._start_scene(1)
	await _run(fe, 120)
	await _save(out + "_story.png")
	fe._goto(fe._enter_options)
	await _run(fe, 80)
	await _save(out + "_options.png")
	for k in [KEY_UP, KEY_UP, KEY_RIGHT, KEY_UP, KEY_RIGHT, KEY_LEFT, KEY_UP, KEY_UP, KEY_RIGHT, KEY_UP, KEY_RIGHT, KEY_UP, KEY_RIGHT, KEY_RIGHT]:
		var e := InputEventKey.new()
		e.keycode = k
		e.pressed = true
		fe._unhandled_input(e)
	await _run(fe, 5)
	await _save(out + "_options2.png")
	fe._goto(fe._enter_scores)
	await _run(fe, 80)
	await _save(out + "_scores.png")
	quit(0)


func _run(fe: FrontEnd, ticks: int) -> void:
	for t in ticks:
		fe._physics_process(0.02)
	for i in 3:
		await process_frame


func _save(path: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("saved ", path, " ", img.get_size())
