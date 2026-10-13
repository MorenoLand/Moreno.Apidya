extends SceneTree
## Headless audio check: renders a few seconds of a level's music and prints timing + levels.
##   redot --headless --path . --script res://tests/test_audio.gd -- --disks=<folder> [--level=1] [--seconds=5] [--wav=out.wav]

func _initialize() -> void:
	var found := DiskLocator.find()
	if found["disks"] == null:
		print("SKIP: ", found["error"])
		quit(0)
		return
	var level := 1
	var seconds := 5.0
	var wav_path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			level = int(a.substr(8))
		elif a.begins_with("--seconds="):
			seconds = float(a.substr(10))
		elif a.begins_with("--wav="):
			wav_path = a.substr(6)
	var m: Dictionary = LevelDefs.MUSIC[level]
	var p := TfmxPlayer.new()
	if not p.setup(found["disks"], m["file"], m["mdat"], m["smpl"]):
		print("setup failed: ", p.error)
		quit(1)
		return
	p.start_song(0)
	var ticks := int(seconds * 50.0)
	var t0 := Time.get_ticks_msec()
	var pcm := PackedByteArray()
	var peak := 0.0
	var sumsq := 0.0
	var n := 0
	for t in ticks:
		var buf := p.render_tick()
		for v in buf:
			peak = maxf(peak, maxf(absf(v.x), absf(v.y)))
			sumsq += v.x * v.x + v.y * v.y
			n += 2
		if wav_path != "":
			for v in buf:
				pcm.append_array(PackedByteArray([0, 0, 0, 0]))
				var i := pcm.size() - 4
				pcm.encode_s16(i, int(clampf(v.x, -1.0, 1.0) * 32767.0))
				pcm.encode_s16(i + 2, int(clampf(v.y, -1.0, 1.0) * 32767.0))
	var ms := Time.get_ticks_msec() - t0
	print("level %d: %.1f s of audio in %d ms (%.1fx real time), %d m68k instructions, peak %.3f rms %.3f, ok=%s" % [
		level, seconds, ms, seconds * 1000.0 / maxf(1.0, float(ms)), p.cpu.instr_count, peak, sqrt(sumsq / maxf(1.0, n)), str(p.ok)])
	if wav_path != "":
		var w := AudioStreamWAV.new()
		w.format = AudioStreamWAV.FORMAT_16_BITS
		w.stereo = true
		w.mix_rate = p.rate
		w.data = pcm
		w.save_to_wav(wav_path)
		print("wrote ", wav_path)
	quit(0)
