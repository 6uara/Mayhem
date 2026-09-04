@tool
class_name ArenaEditorDock
extends VBoxContainer
## The Arena Editor's panel: arena identity, the palette, the problem list and
## the new/load/save/play buttons.
##
## Holds a `PlacementModel` and reads it. Every edit goes through the model, so
## the dock could be deleted tomorrow and the editor would still work headless.

signal arena_changed()
signal focus_requested(cell: Vector3i)
signal play_requested()
signal build_mode_changed(enabled: bool)

const DEFAULT_CATALOG: String = "res://data/arena_pieces/default_catalog.tres"
const ARENA_DIR: String = "res://data/arenas"
## What the model's refusal codes mean to whoever just clicked.
const REFUSAL_TEXT: Dictionary = {
	&"out_of_bounds": "That is outside the grid.",
	&"cell_taken": "There is already a piece of that kind in the cell.",
	&"needs_floor": "That one needs a flat floor tile under it - not a ramp.",
	&"needs_empty": "That one hangs in the air: put it in a cell with no floor.",
	&"too_low": "That one has to go higher up.",
	&"unknown_piece": "That piece is not in the catalog.",
}
## Shared with the in-game editor: one list of grid sizes, two front ends.
const SIZE_PRESETS: Dictionary = ArenaData.SIZE_PRESETS

var model := PlacementModel.new()
var catalog: PieceCatalog
var rules := ValidationRules.new()
var current_path: String = ""
## While this is off the plugin keeps its hands off the 3D viewport: no ghost, no
## preview node in the edited scene, clicks and R belong to Godot again.
##
## Off by default, and deliberately so. The dock is useful while working on any
## scene - the validation list, Play, the arena in hand - but a tool that eats
## the left click of every 3D scene you open is a tool you end up disabling from
## the plugin list, which is worse than having a switch.
var build_mode: bool = false
## Quarter turns applied to the next placed piece.
var pending_rotation: int = 0
var selected_piece: StringName = &""

var _name_edit: LineEdit
var _size_button: OptionButton
var _status: Label
var _palette: ArenaPalettePanel
var _validation: ArenaValidationPanel
var _build_toggle: CheckButton
var _save_dialog: EditorFileDialog
var _load_dialog: EditorFileDialog
var _export_dialog: EditorFileDialog


func _ready() -> void:
	name = "Arena"
	custom_minimum_size = Vector2(280.0, 0.0)
	_build_header()
	_build_mode_toggle()
	_palette = ArenaPalettePanel.new()
	_palette.piece_selected.connect(func(id: StringName) -> void: selected_piece = id)
	_palette.level_changed.connect(func(_level: int) -> void: arena_changed.emit())
	add_child(_palette)
	add_child(HSeparator.new())
	_validation = ArenaValidationPanel.new()
	_validation.issue_activated.connect(func(cell: Vector3i) -> void: focus_requested.emit(cell))
	add_child(_validation)
	_build_buttons()
	_build_dialogs()

	if ResourceLoader.exists(DEFAULT_CATALOG):
		catalog = load(DEFAULT_CATALOG) as PieceCatalog
	model.catalog = catalog
	model.changed.connect(_on_model_changed)
	_palette.set_catalog(catalog)
	new_arena()
	_set_status("Viewport released. Turn BUILD MODE on to place pieces.")


# The plugin's view of the dock

func is_build_mode() -> bool:
	return build_mode


func set_build_mode(enabled: bool) -> void:
	if build_mode == enabled:
		return
	build_mode = enabled
	if _build_toggle != null:
		_build_toggle.button_pressed = enabled
	_set_status("Building: click places, R rotates." if enabled
		else "Viewport released. Turn BUILD MODE on to place pieces.")
	build_mode_changed.emit(enabled)


func get_tool() -> ArenaPalettePanel.Tool:
	return _palette.get_tool()


func get_level() -> int:
	return _palette.get_level()


func get_selected_piece() -> StringName:
	return selected_piece


func rotate_pending() -> void:
	pending_rotation = posmod(pending_rotation + 1, 4)
	_set_status("Rotation: %d deg" % (pending_rotation * 90))


## Applies the active tool at `cell`. The plugin turns a click into a cell; this
## turns a cell into an edit.
func apply_tool_at(cell: Vector3i) -> bool:
	match get_tool():
		ArenaPalettePanel.Tool.PLACE:
			if selected_piece == &"":
				return false
			var refusal: StringName = model.refusal_for(selected_piece, cell, pending_rotation)
			if refusal != &"":
				_set_status(REFUSAL_TEXT.get(refusal, "That piece cannot go there."))
				return false
			return true
		ArenaPalettePanel.Tool.ERASE:
			return model.erase_at(cell) or model.remove_enemy_spawn(cell)
		ArenaPalettePanel.Tool.PLAYER_SPAWN:
			return model.set_player_spawn(cell)
		ArenaPalettePanel.Tool.ENEMY_SPAWN:
			if model.get_enemy_spawn_at(cell) != null:
				return model.remove_enemy_spawn(cell)
			return model.add_enemy_spawn(cell)
	return false


## Asks the model rather than re-deriving the rules: the ghost used to check both
## layers at once and went red over a floor tile, on placements the model was
## perfectly happy to make.
func can_place_at(cell: Vector3i) -> bool:
	if selected_piece == &"" or catalog == null:
		return false
	return model.refusal_for(selected_piece, cell, pending_rotation, true) == &""


# Arena lifecycle

func new_arena() -> void:
	var arena := ArenaData.new()
	arena.arena_name = "Untitled"
	arena.grid_size = SIZE_PRESETS.values()[_size_button.get_selected_id()]
	arena.created_at = Time.get_datetime_string_from_system(true)
	model.arena = arena
	current_path = ""
	_name_edit.text = arena.arena_name
	_palette.set_max_level(arena.grid_size.y)
	_on_model_changed()


func load_arena(path: String) -> void:
	var arena: ArenaData = ArenaIO.load_arena(path)
	if arena == null:
		_set_status("Could not load %s" % path)
		return
	model.arena = arena
	current_path = path
	_name_edit.text = arena.arena_name
	_palette.set_max_level(arena.grid_size.y)
	_select_size_preset(arena.grid_size)
	_set_status("Loaded %s" % path.get_file())
	_on_model_changed()


## Saving is blocked while errors stand: a broken arena on disk is a bug waiting
## to be reported against the game, not against the editor.
func save_arena(path: String) -> bool:
	if not _blocking_issues().is_empty():
		_set_status("Fix the errors before saving.")
		return false
	model.arena.arena_name = _name_edit.text
	var error: Error = ArenaIO.save(model.arena, path)
	if error != OK:
		_set_status("Save failed (%d)." % error)
		return false
	current_path = path
	_set_status("Saved %s" % path.get_file())
	return true


func export_json(path: String) -> void:
	model.arena.arena_name = _name_edit.text
	var error: Error = ArenaIO.save_json(model.arena, path)
	if error == OK:
		_set_status("Exported %s" % path.get_file())
	else:
		_set_status("Export failed (%d)." % error)


func validate_now() -> Array[ValidationIssue]:
	var issues: Array[ValidationIssue] = ArenaValidator.validate(model.arena, catalog, rules)
	_validation.show_issues(issues)
	return issues


# Private

func _blocking_issues() -> Array[ValidationIssue]:
	return ArenaValidator.errors(validate_now())


func _on_model_changed() -> void:
	validate_now()
	arena_changed.emit()


func _build_header() -> void:
	var name_row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Name"
	name_row.add_child(label)
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_edit)
	add_child(name_row)

	var size_row := HBoxContainer.new()
	var size_label := Label.new()
	size_label.text = "Size"
	size_row.add_child(size_label)
	_size_button = OptionButton.new()
	var index: int = 0
	for preset_name: String in SIZE_PRESETS.keys():
		_size_button.add_item(preset_name, index)
		index += 1
	_size_button.select(1)
	_size_button.item_selected.connect(_on_size_selected)
	_size_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_row.add_child(_size_button)
	add_child(size_row)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)


## A CheckButton rather than a menu entry: it has to be visible at a glance,
## because "why is my click not doing anything" and "why did my click place a
## floor tile" are both questions this switch answers.
func _build_mode_toggle() -> void:
	_build_toggle = CheckButton.new()
	_build_toggle.text = "Build mode (3D viewport)"
	_build_toggle.tooltip_text = "While off, the viewport belongs to Godot."
	_build_toggle.button_pressed = build_mode
	_build_toggle.toggled.connect(set_build_mode)
	add_child(_build_toggle)


func _build_buttons() -> void:
	var row := HBoxContainer.new()
	row.add_child(_button("New", new_arena))
	row.add_child(_button("Load", func() -> void: _load_dialog.popup_centered_ratio(0.6)))
	row.add_child(_button("Save", _on_save_pressed))
	add_child(row)
	var row_two := HBoxContainer.new()
	row_two.add_child(_button("Export JSON",
		func() -> void: _export_dialog.popup_centered_ratio(0.6)))
	row_two.add_child(_button("Undo", _on_undo_pressed))
	row_two.add_child(_button("Play", _on_play_pressed))
	add_child(row_two)


func _build_dialogs() -> void:
	_save_dialog = _make_dialog(EditorFileDialog.FILE_MODE_SAVE_FILE, ["*.tres ; Arena"])
	_save_dialog.file_selected.connect(save_arena)
	_load_dialog = _make_dialog(EditorFileDialog.FILE_MODE_OPEN_FILE,
		["*.tres ; Arena", "*.json ; Arena JSON"])
	_load_dialog.file_selected.connect(load_arena)
	_export_dialog = _make_dialog(EditorFileDialog.FILE_MODE_SAVE_FILE, ["*.json ; Arena JSON"])
	_export_dialog.file_selected.connect(export_json)


func _make_dialog(mode: EditorFileDialog.FileMode, filters: Array) -> EditorFileDialog:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = mode
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.current_dir = ARENA_DIR
	for filter: String in filters:
		dialog.add_filter(filter)
	add_child(dialog)
	return dialog


func _on_undo_pressed() -> void:
	if not model.undo():
		_set_status("Nothing to undo.")


func _on_save_pressed() -> void:
	if current_path != "":
		save_arena(current_path)
		return
	_save_dialog.popup_centered_ratio(0.6)


func _on_play_pressed() -> void:
	if not _blocking_issues().is_empty():
		_set_status("Fix the errors before playing.")
		return
	play_requested.emit()


func _on_size_selected(index: int) -> void:
	model.arena.grid_size = SIZE_PRESETS.values()[index]
	_palette.set_max_level(model.arena.grid_size.y)
	_on_model_changed()


func _select_size_preset(size: Vector3i) -> void:
	var values: Array = SIZE_PRESETS.values()
	for index: int in values.size():
		if values[index] == size:
			_size_button.select(index)
			return


func _button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(handler)
	return button


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text
