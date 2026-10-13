class_name MessageScreen
extends Control
## A black screen with a few lines in the original's font: the "CONTINUE? YES NO" question after the last
## ship is lost (the original's routine at $4C340 in file 1 asks it with a credit count that starts at 3),
## and the notice after finishing the easy game. `done` carries 1 for yes / fire, 0 for no.

signal done(result: int)

var _text: OsdText
var _lines := ""
var _choice := false
var _credits := 0
var _yes := true
var _t := 0
var _armed := false             # the fire button must have been up once, so a held button does not answer
var _sent := false


func setup(lines: String, choice: bool = false, credits: int = 0) -> void:
	_lines = lines
	_choice = choice
	_credits = credits


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.color = Color.BLACK
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var arc := AspectRatioContainer.new()
	arc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arc.ratio = 4.0 / 3.0
	add_child(arc)
	var vp := SubViewport.new()
	vp.size = Vector2i(320, 240)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(vp)
	var rect := TextureRect.new()
	rect.texture = vp.get_texture()
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	arc.add_child(rect)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.size = Vector2(320, 240)
	vp.add_child(black)
	_text = OsdText.new()
	_text.position = Vector2(0, 96)
	vp.add_child(_text)
	_refresh()


func _refresh() -> void:
	if not _choice:
		_text.text = _lines
		return
	var blink := (_t / 12) % 2 == 0
	var yes := "YES" if (_yes and blink) or not _yes else "   "
	var no := "NO" if (not _yes and blink) or _yes else "  "
	_text.text = "%s\n\n%s   %s\n\nCREDITS %d" % [_lines, yes, no, _credits]


func _physics_process(_delta: float) -> void:
	if _sent:
		return
	_t += 1
	var fire := Input.is_action_pressed("fire")
	if not fire:
		_armed = true
	if _choice:
		if Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("move_up"):
			_yes = true
		elif Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("move_down"):
			_yes = false
		if _t % 12 == 0:
			_refresh()
	if fire and _armed:
		_answer(1 if (_yes or not _choice) else 0)


func _unhandled_input(event: InputEvent) -> void:
	if _sent or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
		_answer(1 if (_yes or not _choice) else 0)
	elif event.keycode == KEY_ESCAPE:
		_answer(0)


func _answer(result: int) -> void:
	_sent = true
	done.emit(result)
