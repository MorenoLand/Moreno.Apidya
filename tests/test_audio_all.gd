extends SceneTree
## Runs every song and sound effect of every level's module through the replayer and reports failures
## (unsupported 68000 instruction, runaway code). Needs the game's disk images.
##   redot --headless --path . --script res://tests/test_audio_all.gd -- --disks=<folder>

func _initialize() -> void:
	var found := DiskLocator.find()
	if found["disks"] == null:
		print("SKIP: ", found["error"])
		quit(0)
		return
	var failures := 0
	var total := 0
	for level in LevelDefs.MUSIC.keys():
		var m: Dictionary = LevelDefs.MUSIC[level]
		var header: PackedByteArray = (found["disks"] as DiskSet).get_data(m["file"])
		var trackstep := BE.u32(header, 0x1D0)
		var nsfx := maxi(0, (trackstep - 0x200) / 8)
		var songs: Array[int] = []
		for s in 30:
			var st := BE.u16(header, 0x100 + s * 2)
			var en := BE.u16(header, 0x140 + s * 2)
			if st != 0 or en != 0:
				songs.append(s)
		var peak := 0.0
		for s in songs:
			var p := TfmxPlayer.new()
			if not p.setup(found["disks"], m["file"], m["mdat"], m["smpl"], 22050):
				print("level %d song %d: setup failed %s" % [level, s, p.error])
				failures += 1
				continue
			p.start_song(s)
			for t in 150:
				for v in p.render_tick():
					peak = maxf(peak, absf(v.x))
			total += 1
			if not p.ok:
				print("level %d song %d: FAILED %s" % [level, s, p.cpu.last_error])
				failures += 1
		for e in nsfx:
			var p2 := TfmxPlayer.new()
			p2.setup(found["disks"], m["file"], m["mdat"], m["smpl"], 22050)
			p2.start_song(songs[0] if songs.size() > 0 else 0)
			for t in 10:
				p2.render_tick()
			p2.play_sfx(e)
			for t in 60:
				p2.render_tick()
			total += 1
			if not p2.ok:
				print("level %d sfx %d: FAILED %s" % [level, e, p2.cpu.last_error])
				failures += 1
		print("level %d: %d songs, %d effects checked (peak %.2f)" % [level, songs.size(), nsfx, peak])
	print("done: %d runs, %d failures" % [total, failures])
	quit(1 if failures > 0 else 0)
