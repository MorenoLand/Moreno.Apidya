extends SceneTree
## Loads the real start scene and drives it: title -> options -> game -> back to the high score table.
##   redot --headless --path . --script res://tests/test_scene.gd -- --disks=<folder>

var _fail := 0


func _check(cond: bool, what: String) -> void:
	if cond:
		print("ok   ", what)
	else:
		print("FAIL ", what)
		_fail += 1


func _key(node: Object, code: int) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	node.call("_unhandled_input", e)


func _initialize() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	if main._disks == null:
		print("SKIP: no disks")
		quit(0)
		return
	var fe: FrontEnd = main._front
	_check(fe != null and fe._mode == FrontEnd.Mode.ATTRACT, "front end starts in the attract loop")

	_key(fe, KEY_SPACE)
	for i in 60:
		fe._physics_process(0.02)
	_check(fe._mode == FrontEnd.Mode.OPTIONS, "fire on the title opens the options")

	_key(fe, KEY_UP)                       # cursor from START to SOUND TEST
	_check(fe._sel == 6, "cursor moves up")
	for i in 3:
		_key(fe, KEY_UP)                   # ... to LIVES
	_check(fe._sel == 3, "cursor at xtra select")
	_key(fe, KEY_UP)
	_key(fe, KEY_UP)                       # LIVES
	_key(fe, KEY_LEFT)                     # default 5 -> 4
	_check(fe._opts[1] == 1, "lives changes with left")
	_key(fe, KEY_LEFT)
	_key(fe, KEY_LEFT)
	_check(fe._opts[1] == 2, "lives wraps around (3 -> 5)")
	for i in 6:
		_key(fe, KEY_DOWN)
	_check(fe._sel == 7, "cursor back on start")
	_key(fe, KEY_RIGHT)
	_check(fe._on_save, "right moves to save")
	_key(fe, KEY_LEFT)
	var o := fe.game_options()
	_check(o["lives"] == 5 and o["difficulty"] == 2, "game options reflect the choices: %s" % str(o))

	_key(fe, KEY_SPACE)                    # START
	await process_frame
	await process_frame
	var g: Game = main._game
	_check(g != null, "the game starts")
	for i in 30:
		g._physics_process(0.02)
	_check(g.get_score() >= 0, "the game runs")

	# finish the game: ESC returns to the front end with the score
	g._score = 123456
	g.exited.emit()
	await process_frame
	await process_frame
	await process_frame
	var fe2: FrontEnd = main._front
	_check(fe2 != null and fe2._mode == FrontEnd.Mode.NAME, "a high score asks for a name")
	for c in "ikuro":
		var e := InputEventKey.new()
		e.keycode = KEY_A
		e.unicode = c.unicode_at(0)
		e.pressed = true
		fe2._unhandled_input(e)
	_key(fe2, KEY_ENTER)
	for i in 60:
		fe2._physics_process(0.02)
	_check(fe2._mode == FrontEnd.Mode.SCORES, "name entry leads to the table")
	_check(fe2._scores[1]["name"] == "ikuro" and fe2._scores[1]["score"] == 123456, "score inserted at rank 2")
	Settings.set_value("fe_scores", [])        # keep the user's real settings clean
	Settings.set_value("fe_options", [])
	print("scene flow: %d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)
