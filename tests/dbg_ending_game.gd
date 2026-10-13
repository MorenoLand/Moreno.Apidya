extends SceneTree
## Developer tool: runs the Ending node (what the game shows after level 5) with the real renderer and
## saves screenshots every --every frames.
##   redot --path . --script res://tests/dbg_ending_game.gd -- --mode=0 --frames=1200 --every=300
func _initialize() -> void:
	var found := DiskLocator.find()
	var mode := 0
	var frames := 600
	var every := 200
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			mode = int(a.substr(7))
		elif a.begins_with("--frames="):
			frames = int(a.substr(9))
		elif a.begins_with("--every="):
			every = int(a.substr(8))
	var e := Ending.new()
	e.setup(found["disks"], mode)
	root.add_child(e)
	var t0 := Time.get_ticks_msec()
	for f in frames:
		await physics_frame
		if f % every == every - 1:
			await process_frame
			await process_frame
			root.get_texture().get_image().save_png("G:/Development/Working/Amiga/analysis/renders/ending_game_%04d.png" % f)
			print("frame %d at %d ms" % [f, Time.get_ticks_msec() - t0])
	print("ok %s failed %s pc %X done %s frames %d tex %s last_error %s" % [str(e.ok), str(e.cpu.failed), e.cpu.pc, str(e._done), e._frames, str(e._tex), e.cpu.last_error])
	print("done %d frames in %d ms" % [frames, Time.get_ticks_msec() - t0])
	quit(0)
