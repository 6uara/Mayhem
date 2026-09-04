class_name ArenaEditorHUD
extends Control
## The in-game arena editor's interface.
##
## Reports what the player picked and shows what the validator said; it never
## touches the arena itself. Every edit goes through `PlacementModel`, the same
## way the Godot-side dock does, which is what keeps one set of rules behind two
## sets of buttons.

signal tool_changed(tool_mode: int)
signal piece_selected(piece_id: StringName)
signal level_changed(level: int)
signal rotate_pressed()
signal name_changed(arena_name: String)
signal new_pressed()
signal save_pressed()
signal load_requested(path: String)
signal play_pressed()
signal exit_pressed()
signal issue_focused(cell: Vector3i)
signal size_changed(grid_size: Vector3i)
signal delete_requested(path: String)
## Not `theme_changed`: Control already has a signal by that name and redefining
## it stops the whole script from compiling.
signal venue_changed(theme_id: StringName)

## Short on purpose: the whole bar has to fit at 1600 wide with the size picker
## and the file buttons beside it.
const TOOL_NAMES: Array[String] = ["BUILD", "ERASE", "PLAYER", "ENEMY"]
const TOOL_KEYS: Array[String] = ["1", "2", "3", "4"]
## Seconds a pressed DELETE waits for the second press before it forgets.
const DELETE_CONFIRM_TIME: float = 3.0
## The controls panel, as the player reads them.
const HELP_ROWS: Array[Array] = [
	["Left click", "Use the selected tool on the cell"],
	["Right drag", "Orbit the camera"],
	["WASD", "Pan"],
	["Mouse wheel", "Zoom"],
	["1 2 3 4", "Build / Erase / Player spawn / Enemy spawn"],
	["R", "Rotate the piece 90 degrees"],
	["Q / E", "Down / up one level"],
	["Z", "Undo the last edit"],
	["H", "Show or hide this panel"],
]

var _catalog: PieceCatalog
var _tool_buttons: Array[Button] = []
var _piece_buttons: Array[Button] = []
var _piece_ids: Array[StringName] = []
var _name_edit: LineEdit
var _level_label: Label
var _rotation_label: Label
var _status: Label
var _venue_label: Label
var _issue_list: ItemList
var _issue_cells: Array[Vector3i] = []
var _play_button: Button
var _load_panel: PanelContainer
var _load_list: ItemList
var _load_paths: PackedStringArray = PackedStringArray()
var _size_button: OptionButton
var _delete_button: Button
var _delete_armed: bool = false
var _help_panel: PanelContainer
var _theme_button: OptionButton
var _theme_ids: Array[StringName] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top_bar()
	_build_issue_panel()
	_build_palette()
	_build_load_panel()
	_build_help_panel()


func set_catalog(catalog: PieceCatalog) -> void:
	_catalog = catalog
	_rebuild_palette()


func set_arena_name(arena_name: String) -> void:
	if _name_edit != null and _name_edit.text != arena_name:
		_name_edit.text = arena_name


func set_grid_size(grid_size: Vector3i) -> void:
	var index: int = ArenaData.SIZE_PRESETS.values().find(grid_size)
	if index >= 0:
		_size_button.select(index)


func set_theme_id(theme_id: StringName) -> void:
	var index: int = _theme_ids.find(theme_id)
	if index >= 0:
		_theme_button.select(index)


func set_level(level: int) -> void:
	_level_label.text = "LV %d" % level


func set_rotation_steps(rotation: int) -> void:
	_rotation_label.text = "R %d" % (rotation * 90)


func set_status(text: String) -> void:
	_status.text = text


## How the venue has to stretch to fit what is built. Sits under the validation
## list because it is advice about how the arena will look, not a rule it broke.
func set_venue_fit(text: String) -> void:
	_venue_label.text = text
	_venue_label.add_theme_color_override("font_color",
		Tokens.REWARD if text.begins_with("Venue stretches") else Tokens.MUTED)


func select_tool(tool_mode: int) -> void:
	for index: int in _tool_buttons.size():
		_tool_buttons[index].button_pressed = index == tool_mode


func select_piece(piece_id: StringName) -> void:
	for index: int in _piece_buttons.size():
		_piece_buttons[index].button_pressed = _piece_ids[index] == piece_id


## Errors block Play; warnings only colour the row. Same rule as the dock, said
## out loud on the button so it does not look broken when it is disabled.
func show_issues(issues: Array[ValidationIssue]) -> void:
	_issue_list.clear()
	_issue_cells.clear()
	var errors: int = 0
	for issue: ValidationIssue in issues:
		var index: int = _issue_list.add_item(issue.message)
		_issue_list.set_item_custom_fg_color(
			index, Tokens.ENEMY if issue.is_error() else Tokens.REWARD)
		_issue_cells.append(issue.cell)
		if issue.is_error():
			errors += 1
	_play_button.disabled = errors > 0
	_play_button.text = "PLAY" if errors == 0 else "PLAY  (%d errors)" % errors


func open_load_panel(paths: PackedStringArray) -> void:
	_load_paths = paths
	_load_list.clear()
	for path: String in paths:
		_load_list.add_item(path.get_file().get_basename().capitalize())
	if paths.is_empty():
		_load_list.add_item("No saved arenas yet")
		_load_list.set_item_disabled(0, true)
	_load_panel.visible = true


func close_load_panel() -> void:
	_load_panel.visible = false
	_disarm_delete()


func toggle_help() -> void:
	set_help_visible(not _help_panel.visible)


func set_help_visible(shown: bool) -> void:
	_help_panel.visible = shown


func is_typing() -> bool:
	return _name_edit != null and _name_edit.has_focus()


## Anything that swallows clicks and keys, so the screen knows not to build a
## piece under an open panel.
func is_modal_open() -> bool:
	return (_load_panel != null and _load_panel.visible) 		or (_help_panel != null and _help_panel.visible)


# Private

func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.theme_type_variation = &"HUDPanel"
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = Tokens.SCREEN_MARGIN
	bar.offset_right = -Tokens.SCREEN_MARGIN
	bar.offset_top = 24.0
	bar.offset_bottom = 92.0
	add_child(bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)

	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(180.0, 0.0)
	_name_edit.placeholder_text = "arena name"
	_name_edit.text_changed.connect(func(text: String) -> void: name_changed.emit(text))
	row.add_child(_name_edit)

	_size_button = OptionButton.new()
	_size_button.focus_mode = Control.FOCUS_NONE
	var size_index: int = 0
	for preset_name: String in ArenaData.SIZE_PRESETS.keys():
		_size_button.add_item(preset_name, size_index)
		size_index += 1
	_size_button.select(0)
	# Un solo tamano: el control se queda para decir cual es, no para elegirlo.
	_size_button.disabled = ArenaData.SIZE_PRESETS.size() <= 1
	_size_button.item_selected.connect(func(index: int) -> void:
		size_changed.emit(ArenaData.SIZE_PRESETS.values()[index]))
	row.add_child(_size_button)

	for index: int in TOOL_NAMES.size():
		var button := Button.new()
		button.toggle_mode = true
		button.text = "%s  %s" % [TOOL_KEYS[index], TOOL_NAMES[index]]
		button.focus_mode = Control.FOCUS_NONE
		var captured: int = index
		button.pressed.connect(func() -> void: tool_changed.emit(captured))
		row.add_child(button)
		_tool_buttons.append(button)

	_theme_button = OptionButton.new()
	_theme_button.focus_mode = Control.FOCUS_NONE
	_theme_button.tooltip_text = "What surrounds the arena"
	var theme_index: int = 0
	for theme: ArenaTheme in ArenaTheme.list_themes():
		_theme_button.add_item(theme.display_name, theme_index)
		_theme_ids.append(theme.id)
		theme_index += 1
	_theme_button.item_selected.connect(func(index: int) -> void:
		venue_changed.emit(_theme_ids[index]))
	row.add_child(_theme_button)

	_level_label = _bar_label("LV 0")
	row.add_child(_level_label)
	_rotation_label = _bar_label("ROT  0")
	row.add_child(_rotation_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	row.add_child(_action("NEW", func() -> void: new_pressed.emit()))
	row.add_child(_action("SAVE", func() -> void: save_pressed.emit()))
	row.add_child(_action("LOAD", func() -> void: load_requested.emit("")))
	_play_button = _action("PLAY", func() -> void: play_pressed.emit())
	row.add_child(_play_button)
	row.add_child(_action("EXIT", func() -> void: exit_pressed.emit()))
	row.add_child(_action("?", toggle_help))


func _build_issue_panel() -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"HUDPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -380.0
	panel.offset_right = -Tokens.SCREEN_MARGIN
	panel.offset_top = 108.0
	panel.offset_bottom = 400.0
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var title := Label.new()
	title.theme_type_variation = &"HUDLabel"
	title.text = "VALIDATION"
	title.add_theme_color_override("font_color", Tokens.MUTED)
	column.add_child(title)

	_issue_list = ItemList.new()
	_issue_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_issue_list.custom_minimum_size = Vector2(0.0, 200.0)
	_issue_list.item_selected.connect(_on_issue_selected)
	column.add_child(_issue_list)

	_venue_label = Label.new()
	_venue_label.theme_type_variation = &"HUDLabel"
	_venue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_venue_label.add_theme_color_override("font_color", Tokens.MUTED)
	column.add_child(_venue_label)

	_status = Label.new()
	_status.theme_type_variation = &"HUDLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Tokens.MUTED)
	column.add_child(_status)


func _build_palette() -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"HUDPanel"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = Tokens.SCREEN_MARGIN
	panel.offset_right = -Tokens.SCREEN_MARGIN
	panel.offset_top = -132.0
	panel.offset_bottom = -Tokens.SCREEN_MARGIN
	panel.name = "Palette"
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 10)
	scroll.add_child(row)


func _rebuild_palette() -> void:
	var row: HBoxContainer = get_node("Palette").get_child(0).get_child(0) as HBoxContainer
	for child: Node in row.get_children():
		row.remove_child(child)
		child.queue_free()
	_piece_buttons.clear()
	_piece_ids.clear()
	if _catalog == null:
		return
	for piece: PieceDefinition in _catalog.pieces:
		if piece == null:
			continue
		var button := Button.new()
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(132.0, 64.0)
		button.text = piece.display_name.to_upper()
		button.tooltip_text = "%s - %s" % [
			piece.id, PieceDefinition.Category.keys()[int(piece.category)].capitalize()]
		button.add_theme_color_override("font_color", piece.greybox_color.lightened(0.35))
		var captured: StringName = piece.id
		button.pressed.connect(func() -> void: piece_selected.emit(captured))
		row.add_child(button)
		_piece_buttons.append(button)
		_piece_ids.append(piece.id)


func _build_load_panel() -> void:
	_load_panel = PanelContainer.new()
	_load_panel.theme_type_variation = &"HUDPanel"
	_load_panel.set_anchors_preset(Control.PRESET_CENTER)
	_load_panel.custom_minimum_size = Vector2(420.0, 320.0)
	_load_panel.offset_left = -210.0
	_load_panel.offset_right = 210.0
	_load_panel.offset_top = -160.0
	_load_panel.offset_bottom = 160.0
	_load_panel.visible = false
	add_child(_load_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_load_panel.add_child(column)
	var title := Label.new()
	title.theme_type_variation = &"HUDLabel"
	title.text = "YOUR ARENAS"
	column.add_child(title)
	_load_list = ItemList.new()
	_load_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_load_list.item_activated.connect(_on_load_activated)
	column.add_child(_load_list)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.add_child(_action("OPEN", _on_load_confirmed))
	_delete_button = _action("DELETE", _on_delete_pressed)
	_delete_button.add_theme_color_override("font_color", Tokens.ENEMY)
	buttons.add_child(_delete_button)
	buttons.add_child(_action("CANCEL", close_load_panel))
	column.add_child(buttons)


func _on_load_activated(index: int) -> void:
	_open_index(index)


func _on_load_confirmed() -> void:
	var selected: PackedInt32Array = _load_list.get_selected_items()
	if selected.is_empty():
		return
	_open_index(selected[0])


func _open_index(index: int) -> void:
	if index < 0 or index >= _load_paths.size():
		return
	close_load_panel()
	load_requested.emit(_load_paths[index])


## Two presses, not a dialog: deleting is destructive enough to deserve a beat
## of hesitation and cheap enough not to deserve a modal on top of a modal.
func _on_delete_pressed() -> void:
	var selected: PackedInt32Array = _load_list.get_selected_items()
	if selected.is_empty() or selected[0] >= _load_paths.size():
		return
	if not _delete_armed:
		_delete_armed = true
		_delete_button.text = "SURE?"
		get_tree().create_timer(DELETE_CONFIRM_TIME).timeout.connect(_disarm_delete)
		return
	var path: String = _load_paths[selected[0]]
	_disarm_delete()
	delete_requested.emit(path)


func _disarm_delete() -> void:
	_delete_armed = false
	if _delete_button != null:
		_delete_button.text = "DELETE"


func _build_help_panel() -> void:
	_help_panel = PanelContainer.new()
	_help_panel.theme_type_variation = &"HUDPanel"
	_help_panel.set_anchors_preset(Control.PRESET_CENTER)
	_help_panel.offset_left = -280.0
	_help_panel.offset_right = 280.0
	_help_panel.offset_top = -220.0
	_help_panel.offset_bottom = 220.0
	_help_panel.visible = false
	add_child(_help_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_help_panel.add_child(column)

	var title := Label.new()
	title.theme_type_variation = &"HUDLabel"
	title.text = "BUILDING AN ARENA"
	title.add_theme_color_override("font_color", Tokens.PLAYER)
	column.add_child(title)

	var intro := Label.new()
	intro.theme_type_variation = &"HUDLabel"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.text = "Lay a floor, put down one player spawn and at least one enemy spawn, "		+ "and the arena is playable. The panel on the right tells you what is missing."
	intro.add_theme_color_override("font_color", Tokens.MUTED)
	column.add_child(intro)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	for row_data: Array in HELP_ROWS:
		var key := Label.new()
		key.theme_type_variation = &"HUDLabel"
		key.text = row_data[0]
		key.custom_minimum_size = Vector2(150.0, 0.0)
		key.add_theme_color_override("font_color", Tokens.REWARD)
		grid.add_child(key)
		var text := Label.new()
		text.theme_type_variation = &"HUDLabel"
		text.text = row_data[1]
		text.add_theme_color_override("font_color", Tokens.TEXT)
		grid.add_child(text)
	column.add_child(grid)

	var close := _action("GOT IT", func() -> void: set_help_visible(false))
	close.custom_minimum_size = Vector2(0.0, 40.0)
	column.add_child(close)


func _on_issue_selected(index: int) -> void:
	if index >= 0 and index < _issue_cells.size():
		issue_focused.emit(_issue_cells[index])


func _bar_label(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"HUDLabel"
	label.text = text
	label.custom_minimum_size = Vector2(56.0, 0.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Tokens.PLAYER)
	return label


func _action(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(handler)
	return button
