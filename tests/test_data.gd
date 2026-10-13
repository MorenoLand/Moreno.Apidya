extends SceneTree
## Headless data check. Needs the game's disk images:
##   redot --headless --path . --script res://tests/test_data.gd -- --disks=<folder with Disk.1/Disk.2>
## (or set APIDYA_DISKS, or put the files in assets/original/)

func _init() -> void:
	var found := DiskLocator.find()
	if found["disks"] == null:
		print("SKIP: ", found["error"])
		quit(0)
		return
	var ds: DiskSet = found["disks"]
	print("disk set ok: ", ds.source_path, " (", ds.files.size(), " files)")
	for lv in LevelDefs.LEVELS.keys():
		if LevelDefs.LEVELS[lv]["cols"] == 0:
			continue
		var t := Time.get_ticks_msec()
		var d := LevelData.load_level(ds, lv)
		print("level %d %-8s cols=%d bobs=%d player_variants=%d waves=%d  (%d ms)" % [lv, d.name, d.cols,
			d.bob_frames.size(), d.player_frames.size(), d.waves.size(), Time.get_ticks_msec() - t])
	quit(0)
