class_name ArenaSelect
extends Control
## The Play screen, once there is more than one arena to play.
##
## Only opens when the choice exists: with a single arena installed, pressing
## Play has to start a run, not ask a question with one answer.

signal arena_chosen(path: String)
signal closed()

const SHIPPED_TAG: String = "MAYHEM"
const YOURS_TAG: String = "YOURS"

@onready var _rows: VBoxContainer = $Panel/Margin/Layout/Scroll/Rows
@onready var _play_button: Button = $Panel/Margin/Layout/Footer/PlayButton
@onready var _back_button: Button = $Panel/Margin/Layout/Footer/BackButton

var _entries: Array[Dictionary] = []
var _selected: int = 0
var _buttons: Array[Button] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_play_button.pressed.connect(_on_play_pressed)
	_back_button.pressed.connect(close)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# Public API

func open() -> void:
	_rebuild()
	visible = true
	if _buttons.is_empty():
		_play_button.grab_focus()
	else:
		_buttons[_selected].grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


# Private

func _rebuild() -> void:
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_buttons.clear()
	_entries = ArenaSession.list_playable()
	# Reopening keeps the last choice under the cursor, unless that arena is gone.
	_selected = 0
	for index: int in _entries.size():
		if _entries[index]["path"] == ArenaSession.run_arena_path:
			_selected = index
	for index: int in _entries.size():
		var row: Button = _build_row(_entries[index], index)
		_rows.add_child(row)
		_buttons.append(row)
	_highlight()


func _build_row(entry: Dictionary, index: int) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(0.0, 52.0)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text = "  %s        %s  ·  %d pieces" % [
		entry["name"], SHIPPED_TAG if entry["shipped"] else YOURS_TAG, entry["pieces"]]
	button.add_theme_color_override("font_color",
		Tokens.TEXT if bool(entry["shipped"]) else Tokens.PLAYER)
	button.pressed.connect(func() -> void: _select(index))
	# Double click, or Enter on a focused row, plays it: the second press should
	# not need the mouse to travel to the corner.
	button.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.double_click:
			_select(index)
			_on_play_pressed())
	return button


func _select(index: int) -> void:
	_selected = index
	_highlight()


func _highlight() -> void:
	for index: int in _buttons.size():
		_buttons[index].button_pressed = index == _selected
	_play_button.disabled = _buttons.is_empty()


func _on_play_pressed() -> void:
	if _selected < 0 or _selected >= _entries.size():
		return
	visible = false
	arena_chosen.emit(_entries[_selected]["path"])
