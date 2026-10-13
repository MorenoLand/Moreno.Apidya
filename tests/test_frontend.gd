extends SceneTree
## Checks the front-end data (title, story, options, high scores) read from the original disks.
##   redot --headless --path . --script res://tests/test_frontend.gd -- --disks=<folder>

var _fail := 0


func _check(cond: bool, what: String) -> void:
	if cond:
		print("ok   ", what)
	else:
		print("FAIL ", what)
		_fail += 1


func _initialize() -> void:
	var found := DiskLocator.find()
	if found["disks"] == null:
		print("SKIP: ", found["error"])
		quit(0)
		return
	var fe := FrontEndData.new(found["disks"])

	var title := fe.picture(FrontEndData.PIC_TITLE)
	_check(title.size() == 40960, "title picture decodes to 4 planes of 320x256")
	var idx := FrontEndData.planar_to_indexed(title, 0, 40, 256, 4, 0x2800)
	var used := {}
	for v in idx:
		used[v] = true
	_check(used.size() >= 8, "title uses many colours (%d)" % used.size())

	var pal := fe.palette(FrontEndData.PAL_TITLE)
	_check(pal[0] == 0 and pal[12] == 0xFFF, "title palette: black background, white 12")

	var pages := fe.story_pages()
	_check(pages.size() == 10, "ten story pages")
	_check(pages[1]["text"].begins_with("    19xx a.d."), "first story page text")
	_check(pages[1]["frames"] == 250, "first story page duration")

	var scores := fe.default_scores()
	_check(scores[0]["name"] == "kaiko" and scores[0]["score"] == 150000, "default top score")
	_check(scores[4]["name"] == "masamune" and scores[4]["score"] == 20000, "default fifth score")
	var opts := fe.default_options()
	_check(opts.size() == 7 and opts[0] == 2, "default options (level normal)")

	var lv := fe.option_strings(0)
	_check(lv.size() == 4 and lv[0] == "practice" and lv[2].strip_edges() == "normal", "level choices")
	var team := fe.option_strings(2)
	_check(team.size() == 3 and team[1].strip_edges() == "simul", "team mode choices")

	var snd := fe.sound_test_entries()
	_check(snd.size() == 25 and snd[0]["name"].strip_edges() == "sound stop", "sound test list")
	_check(snd[1]["name"].strip_edges() == "meadows edge 1" and snd[1]["module"] == 6 and snd[1]["song"] == 0,
			"sound test entry 1 -> module 6 song 0")

	# font: the letter 'A' must have some pixels, space none
	var plane := PackedByteArray()
	plane.resize(40 * 16)
	fe.draw_text(plane, 0, 0, "a b")
	var a_bits := 0
	var sp_bits := 0
	for r in 8:
		a_bits += plane[r * 40]
		sp_bits += plane[r * 40 + 1]
	_check(a_bits != 0 and sp_bits == 0, "font draws letters, space is blank")

	# the title music module (embedded in the front-end file) runs
	var p := TfmxPlayer.new()
	_check(p.setup(found["disks"], 0, 0xE000, 0x343F2), "menu module initialises")
	p.start_song(0)
	var peak := 0.0
	for t in 100:
		for v in p.render_tick():
			peak = maxf(peak, absf(v.x))
	_check(peak > 0.01, "menu music is audible (peak %.3f)" % peak)

	print("front end: %d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)
