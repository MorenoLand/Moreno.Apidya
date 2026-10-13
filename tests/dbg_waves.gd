extends SceneTree
## Investigation: lists the waves of a level.

func _initialize() -> void:
	var level := 5
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			level = int(a.substr(8))
	var found := DiskLocator.find()
	var lv := LevelData.load_level(found["disks"], level)
	print("waves: ", lv.waves.size())
	var groups := 0
	var singles := 0
	for w in lv.waves:
		if w["group"]:
			groups += 1
		else:
			singles += 1
	print("groups %d singles %d" % [groups, singles])
	for i in lv.waves.size():
		var w: Dictionary = lv.waves[i]
		if w["group"]:
			var f := lv.decode_formation(w["list"])
			var types := []
			for e in f:
				types.append("%d/%04X" % [e["type"], e["handler"]])
			print("col %4d group list %04X req %d hold %d: %s" % [w["col"], w["list"], w["required"], w["hold"], str(types)])
		else:
			print("col %4d single type %d x %d y %d hp %d handler %04X" % [w["col"], w["type"], w["x"], w["y"], w["hp"], w["handler"]])
	quit(0)
