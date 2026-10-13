extends SceneTree
## Investigation: what the level 5 scroller generated.

func _initialize() -> void:
	var found := DiskLocator.find()
	var disks: DiskSet = found["disks"]
	var t0 := Time.get_ticks_msec()
	var lv := LevelData.load_level(disks, 5)
	print("loaded in %d ms, cols %d, words %d" % [Time.get_ticks_msec() - t0, lv.cols, lv.map_words.size()])
	var used := 0
	var rows_used := {}
	for i in lv.map_words.size():
		if lv.map_words[i] != 0x3FF:
			used += 1
			rows_used[i / lv.cols] = true
	print("tiles used ", used, " rows ", rows_used.keys())
	for r in [0, 1, 12, 13, 14]:
		var line := ""
		for c in 40:
			line += "%03X " % lv.map_words[r * lv.cols + c]
		print("row %d: %s" % [r, line])
	quit(0)
