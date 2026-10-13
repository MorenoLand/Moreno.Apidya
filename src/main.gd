extends Control
## Start screen: finds the user's disk images (or asks for them) and launches a level.

var _disks: DiskSet
var _status: Label
var _buttons: VBoxContainer
var _dialog: FileDialog
var _game: Control
var _menu: Control


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
	_menu = box

	var title := Label.new()
	title.text = "APIDYA"
	title.add_theme_font_size_override("font_size", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)

	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 6)
	box.add_child(_buttons)

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
		_show_levels()
	else:
		_show_need_files(res["error"])


func _clear_buttons() -> void:
	for c in _buttons.get_children():
		c.queue_free()


func _show_need_files(error: String) -> void:
	_clear_buttons()
	_status.text = "Apidya's game files are needed.\n%s\n\nPut Disk.1 and Disk.2 (WHDLoad install) in assets/original/,\nor choose the folder that contains them." % error
	var b := Button.new()
	b.text = "Choose folder..."
	b.pressed.connect(func() -> void: _dialog.popup_centered())
	_buttons.add_child(b)


func _show_levels() -> void:
	_clear_buttons()
	_status.text = "Choose a level"
	for lv in LevelDefs.LEVELS.keys():
		var def: Dictionary = LevelDefs.LEVELS[lv]
		var b := Button.new()
		b.text = "Level %d - %s" % [lv, def["name"]]
		b.disabled = def["cols"] == 0
		b.pressed.connect(_start_level.bind(lv))
		_buttons.add_child(b)


func _on_dir_selected(dir: String) -> void:
	var res := DiskLocator.open_folder(dir)
	if res["disks"] != null:
		_disks = res["disks"]
		_show_levels()
	else:
		_show_need_files(res["error"])


func _start_level(lv: int) -> void:
	_status.text = "Loading level %d..." % lv
	await get_tree().process_frame
	var g := Game.new()
	g.setup(_disks, lv)
	g.exited.connect(_on_game_exited)
	g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game = g
	_menu.visible = false
	add_child(g)


func _on_game_exited() -> void:
	if _game:
		_game.queue_free()
		_game = null
	_menu.visible = true
	_show_levels()
