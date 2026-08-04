class_name LeaderboardPanel
extends Control
## The run history SaveManager has been writing since Phase 4, finally shown.
##
## Scores were persisted to disk from the first match and read back by nothing, so
## the whole reason to chase a par time - beating your own best - was invisible.
##
## Rows are built from the data rather than authored, because the table is empty on
## a first run and ten deep later, and an authored table has to fake both.

signal closed()

const COLUMNS: Array[String] = ["#", "SCORE", "WAVES", "TIME", "DATE"]
## Relative widths. Score and date carry the most, the rank the least.
const WEIGHTS: Array[float] = [0.5, 1.4, 1.0, 1.0, 2.2]

@onready var _rows: VBoxContainer = $Panel/Margin/Layout/Scroll/Rows
@onready var _empty: Label = $Panel/Margin/Layout/EmptyState
@onready var _back_button: Button = $Panel/Margin/Layout/Footer/BackButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
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
	_back_button.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


# Private

func _rebuild() -> void:
	for child: Node in _rows.get_children():
		child.queue_free()

	var entries: Array[Dictionary] = SaveManager.get_entries()
	# A run nobody has taken yet should say so, not show an empty grid the player
	# has to interpret.
	_empty.visible = entries.is_empty()
	if entries.is_empty():
		return

	_rows.add_child(_make_row(COLUMNS, true))
	for index: int in entries.size():
		var entry: Dictionary = entries[index]
		_rows.add_child(_make_row([
			"%d" % (index + 1),
			"%d" % int(entry.get("score", 0)),
			"%d" % int(entry.get("waves", 0)),
			_format_time(float(entry.get("time", 0.0))),
			String(entry.get("date", "-")),
		], false))


func _make_row(values: Array, is_header: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	for index: int in values.size():
		var label := Label.new()
		label.text = String(values[index])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_stretch_ratio = WEIGHTS[index]
		if is_header:
			label.theme_type_variation = &"HUDLabel"
		else:
			# Monospace for the numbers, so ranks and scores line up down the column
			# instead of dancing as digit counts change.
			label.theme_type_variation = &"Keybind" if index != 1 else &"NumSecond"
		row.add_child(label)
	return row


func _format_time(seconds: float) -> String:
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]
