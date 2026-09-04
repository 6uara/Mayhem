@tool
class_name ArenaPalettePanel
extends VBoxContainer
## The catalog, the active tool and the working height. Pure presentation: it
## reports what the designer picked and never touches the arena itself.

signal piece_selected(piece_id: StringName)
signal tool_changed(tool_mode: int)
signal level_changed(level: int)

enum Tool { PLACE, ERASE, PLAYER_SPAWN, ENEMY_SPAWN }

const TOOL_NAMES: Array[String] = ["Place", "Erase", "Player spawn", "Enemy spawn"]

var _tool_button: OptionButton
var _level_spin: SpinBox
var _piece_list: ItemList
var _piece_ids: Array[StringName] = []


func _ready() -> void:
	var tool_row := HBoxContainer.new()
	tool_row.add_child(_label("Tool"))
	_tool_button = OptionButton.new()
	for index: int in TOOL_NAMES.size():
		_tool_button.add_item(TOOL_NAMES[index], index)
	_tool_button.item_selected.connect(func(index: int) -> void: tool_changed.emit(index))
	_tool_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool_row.add_child(_tool_button)
	add_child(tool_row)

	var level_row := HBoxContainer.new()
	level_row.add_child(_label("Level"))
	_level_spin = SpinBox.new()
	_level_spin.min_value = 0
	_level_spin.max_value = 7
	_level_spin.value_changed.connect(func(value: float) -> void: level_changed.emit(int(value)))
	level_row.add_child(_level_spin)
	add_child(level_row)

	_piece_list = ItemList.new()
	_piece_list.custom_minimum_size = Vector2(0.0, 220.0)
	_piece_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_piece_list.item_selected.connect(_on_piece_selected)
	add_child(_piece_list)


func set_catalog(catalog: PieceCatalog) -> void:
	_piece_ids.clear()
	if _piece_list == null:
		return
	_piece_list.clear()
	if catalog == null:
		return
	for piece: PieceDefinition in catalog.pieces:
		if piece == null:
			continue
		var index: int = _piece_list.add_item(
			"%s  (%s)" % [piece.display_name, _category_name(piece.category)], piece.icon)
		_piece_list.set_item_tooltip(index, "id: %s" % piece.id)
		_piece_ids.append(piece.id)
	if not _piece_ids.is_empty():
		_piece_list.select(0)
		piece_selected.emit(_piece_ids[0])


func set_max_level(level: int) -> void:
	if _level_spin != null:
		_level_spin.max_value = maxi(level - 1, 0)


func get_level() -> int:
	return int(_level_spin.value) if _level_spin != null else 0


func get_tool() -> Tool:
	if _tool_button == null:
		return Tool.PLACE
	return _tool_button.get_selected_id()


# Private

func _on_piece_selected(index: int) -> void:
	if index >= 0 and index < _piece_ids.size():
		piece_selected.emit(_piece_ids[index])


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(64.0, 0.0)
	return label


func _category_name(category: PieceDefinition.Category) -> String:
	return PieceDefinition.Category.keys()[int(category)].capitalize()
