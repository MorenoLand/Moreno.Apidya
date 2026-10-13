extends Control
## Entry point: finds the user's disk images (or asks for them), then runs the front end and the game.

var _disks: DiskSet
var _status: Label
var _prompt: Control
var _dialog: FileDialog
var _front: FrontEnd
var _game: Game
var _ending: Ending
var _options := {}
var _level_no := 1


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	_prompt = box

	var title := Label.new()
	title.text = "APIDYA"
	title.add_theme_font_size_override("font_size", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)

	var choose := Button.new()
	choose.text = "Choose folder..."
	choose.pressed.connect(func() -> void: _dialog.popup_centered())
	box.add_child(choose)

	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.title = "Select the folder that contains Disk.1 and Disk.2"
	_dialog.dir_selected.connect(_on_dir_selected)
	_dialog.size = Vector2i(800, 500)
	add_child(_dialog)

	var res := DiskLocator.find()
	if res["disks"] != null:
		_disks = res["disks"]
		_open_front_end()
	else:
		_show_need_files(res["error"])


func _show_need_files(error: String) -> void:
	_prompt.visible = true
	_status.text = "Apidya's game files are needed.\n%s\n\nPut Disk.1 and Disk.2 (WHDLoad install) in assets/original/,\nor choose the folder that contains them." % error


func _on_dir_selected(dir: String) -> void:
	var res := DiskLocator.open_folder(dir)
	if res["disks"] != null:
		_disks = res["disks"]
		_open_front_end()
	else:
		_show_need_files(res["error"])


func _open_front_end(result: Dictionary = {}) -> void:
	_prompt.visible = false
	_front = FrontEnd.new()
	_front.setup(_disks, result)
	_front.start_game.connect(_on_start_game)
	_front.quit_requested.connect(func() -> void: get_tree().quit())
	add_child(_front)


func _on_start_game(options: Dictionary) -> void:
	_options = options
	if _front:
		_front.queue_free()
		_front = null
	_begin_level(int(options["level"]))


func _begin_level(level: int) -> void:
	_level_no = level
	_game = Game.new()
	_game.setup(_disks, level, _options)
	_game.exited.connect(_on_game_exited)
	_game.level_complete.connect(_on_level_complete)
	add_child(_game)


## A level was cleared: the score, ships and power-ups go on to the next one; after the last the game is won.
func _on_level_complete(carry: Dictionary) -> void:
	if _game:
		_game.queue_free()
		_game = null
	var score := int(carry["score"])
	var diff := int(_options.get("difficulty", 2))
	# the original's driver: after level 4 the easy game ends (practice has no ending at all), the normal and
	# hard games go on to level 5; its ending program gets 0 / 1 (hard) after level 5 and 2 after level 4
	if _level_no == 4 and diff < 2:
		if diff == 0:
			_open_front_end({"score": score, "difficulty": diff})
		else:
			_begin_ending(2, score)
		return
	if _level_no >= 5:
		_begin_ending(1 if diff == 3 else 0, score)
		return
	_options["carry"] = carry
	_begin_level(_level_no + 1)


func _begin_ending(mode: int, score: int) -> void:
	_ending = Ending.new()
	_ending.setup(_disks, mode)
	_ending.finished.connect(func() -> void:
		if _ending:
			_ending.queue_free()
			_ending = null
		_open_front_end({"score": score, "difficulty": _options.get("difficulty", 2)}))
	add_child(_ending)


func _on_game_exited() -> void:
	var score := 0
	if _game:
		score = _game.get_score()
		_game.queue_free()
		_game = null
	_open_front_end({"score": score, "difficulty": _options.get("difficulty", 2)})
