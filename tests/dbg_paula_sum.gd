extends SceneTree
## Developer tool: renders some seconds of a level's music and prints a checksum of the samples, to compare
## two versions of the Paula model. Also prints how long a tick takes.
##   redot --headless --path . --script res://tests/dbg_paula_sum.gd -- --level=1 --ticks=300
func _initialize() -> void:
	var level := 1
	var ticks := 300
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			level = int(a.substr(8))
		elif a.begins_with("--ticks="):
			ticks = int(a.substr(8))
	var disks: DiskSet = DiskLocator.find()["disks"]
	var m: Dictionary = LevelDefs.MUSIC[level]
	var p := TfmxPlayer.new()
	if not p.setup(disks, m["file"], m["mdat"], m["smpl"]):
		print("setup failed: ", p.error)
		quit(1)
		return
	p.start_song(0)
	var sum := 0
	var peak := 0.0
	var t0 := Time.get_ticks_msec()
	for t in ticks:
		if t == 120:
			p.play_sfx(14)
		var buf := p.render_tick()
		sum = (sum * 31 + hash(buf)) & 0x7FFFFFFF
		for i in range(0, buf.size(), 50):
			peak = maxf(peak, absf(buf[i].x))
	print("level %d: %d ticks, checksum %d, peak %.3f, %d ms (%.1f ms/tick)" % [level, ticks, sum, peak, Time.get_ticks_msec() - t0, float(Time.get_ticks_msec() - t0) / ticks])
	quit(0)
