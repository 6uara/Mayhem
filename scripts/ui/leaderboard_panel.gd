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

const COLUMNS: Array[String] = ["#", "NAME", "SCORE", "WAVES", "MODE", "TIME", "DATE",
	"TROPHIES"]
## Relative widths. Name, score and date carry the most, the rank the least.
const WEIGHTS: Array[float] = [0.5, 1.8, 1.4, 0.9, 1.1, 1.0, 1.8, 3.0]
## Indice de la columna del puntaje, que es la que va en la tipografia grande.
const SCORE_COLUMN: int = 2
## Y la de los trofeos, que no es texto sino una hilera de fichas.
const TROPHY_COLUMN: int = 7
## Cuantas fichas entran en una fila antes de resumir el resto en un "+N". Una
## run excepcional puede ganar ocho trofeos, y ocho fichas en una fila de tabla
## dejan de leerse como logros y pasan a ser ruido.
const MAX_CHIPS: int = 4
## Alto de la ficha de trofeo. Del alto de una fila de tabla: el trofeo acompaña
## a la run, no compite con el puntaje.
const CHIP_BOX: float = 22.0

@onready var _rows: VBoxContainer = $Panel/Margin/Layout/Scroll/Rows
@onready var _scroll: ScrollContainer = $Panel/Margin/Layout/Scroll
@onready var _empty: Label = $Panel/Margin/Layout/EmptyState
@onready var _back_button: Button = $Panel/Margin/Layout/Footer/BackButton


## Que arena se esta mirando. Una tabla por arena: ver SaveManager.
var arena_id: String = SaveManager.DEFAULT_ARENA_ID
var _arena_picker: OptionButton
var _arena_ids: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_back_button.pressed.connect(close)
	_build_arena_picker()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# Public API

## Abre en la arena pedida (la de la proxima run, desde el menu), que es la
## tabla que el jugador quiere ver; despues se cambia con el selector.
func open(preferred_arena: String = "") -> void:
	if preferred_arena != "":
		arena_id = preferred_arena
	_refresh_arena_picker()
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

	var entries: Array[Dictionary] = SaveManager.get_entries_for(arena_id)
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
			String(entry.get("name", SaveManager.DEFAULT_NAME)),
			"%d" % int(entry.get("score", 0)),
			"%d" % int(entry.get("waves", 0)),
			GameManager.mode_label(int(entry.get("mode", 0))),
			_format_time(float(entry.get("time", 0.0))),
			String(entry.get("date", "-")),
			entry.get("trophies", []),
		], false))


func _build_arena_picker() -> void:
	_arena_picker = OptionButton.new()
	_arena_picker.name = "ArenaPicker"
	_arena_picker.tooltip_text = "Each arena keeps its own ten best runs."
	_arena_picker.item_selected.connect(func(index: int) -> void:
		if index >= 0 and index < _arena_ids.size():
			arena_id = _arena_ids[index]
			_rebuild())
	var layout: Node = _scroll.get_parent()
	layout.add_child(_arena_picker)
	layout.move_child(_arena_picker, _scroll.get_index())


func _refresh_arena_picker() -> void:
	_arena_picker.clear()
	_arena_ids.clear()
	var arenas: Array[Dictionary] = SaveManager.get_arenas()
	var has_current: bool = false
	for arena: Dictionary in arenas:
		if String(arena["id"]) == arena_id:
			has_current = true
	if not has_current:
		arenas.push_front({"id": arena_id, "name": _name_for(arena_id)})
	for arena: Dictionary in arenas:
		_arena_ids.append(String(arena["id"]))
		_arena_picker.add_item(String(arena["name"]))
	_arena_picker.select(_arena_ids.find(arena_id))
	_arena_picker.visible = _arena_ids.size() > 1


func _name_for(id: String) -> String:
	if id == SaveManager.DEFAULT_ARENA_ID:
		return SaveManager.DEFAULT_ARENA_NAME
	return id.get_file().get_basename()


func _make_row(values: Array, is_header: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	for index: int in values.size():
		if index == TROPHY_COLUMN and not is_header:
			row.add_child(_make_trophies(values[index] as Array))
			continue
		var label := Label.new()
		label.text = String(values[index])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_stretch_ratio = WEIGHTS[index]
		if is_header:
			label.theme_type_variation = &"HUDLabel"
		else:
			# Monospace for the numbers, so ranks and scores line up down the column
			# instead of dancing as digit counts change.
			label.theme_type_variation = &"Keybind" if index != SCORE_COLUMN 				else &"NumSecond"
		row.add_child(label)
	return row


## La hilera de fichas de una run. Vacia cuando no gano ninguno - y una fila sin
## trofeos es informacion, no un hueco: dice que esa run fue solo puntaje.
##
## Las fichas son texto hasta que exista el set de iconos (ver el handoff de
## iconografia): cuando lo haya, lo unico que cambia es lo que se mete adentro
## del chip, no la columna ni la fila.
func _make_trophies(trophy_ids: Array) -> Control:
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_stretch_ratio = WEIGHTS[TROPHY_COLUMN]
	box.add_theme_constant_override(&"separation", 6)
	if trophy_ids.is_empty():
		return box

	var shown: int = mini(trophy_ids.size(), MAX_CHIPS)
	for i: int in shown:
		var id := StringName(trophy_ids[i])
		box.add_child(_make_chip(id))

	if trophy_ids.size() > shown:
		var more := Label.new()
		more.text = "+%d" % (trophy_ids.size() - shown)
		more.theme_type_variation = &"HUDLabel"
		more.add_theme_color_override(&"font_color", Tokens.MUTED)
		more.tooltip_text = _describe_all(trophy_ids)
		more.mouse_filter = Control.MOUSE_FILTER_PASS
		box.add_child(more)
	return box


## Un trofeo: el icono si existe, y el nombre en texto si no.
##
## Los dos llevan el mismo tooltip, que es lo unico que explica que significa
## CIRUJANO - y con icono hace mas falta que sin el, porque un dibujo chico no
## se explica solo.
func _make_chip(id: StringName) -> Control:
	var icon: Texture2D = IconSet.trophy(id)
	if icon != null:
		var chip: MayhemIcon = IconSet.make(IconSet.TROPHY, id, Tokens.REWARD, CHIP_BOX)
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.tooltip_text = "%s\n%s" % [RunRecord.get_label(id),
			RunRecord.get_description(id)]
		return chip
	var label := Label.new()
	label.text = RunRecord.get_label(id)
	label.theme_type_variation = &"HUDLabel"
	label.add_theme_color_override(&"font_color", Tokens.REWARD)
	label.tooltip_text = RunRecord.get_description(id)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	return label


## Todos los trofeos de la run, uno por linea. Es lo que el "+N" tiene que poder
## contestar cuando alguien le pregunta.
func _describe_all(trophy_ids: Array) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for id: Variant in trophy_ids:
		lines.append(RunRecord.get_label(StringName(id)))
	return "\n".join(lines)


func _format_time(seconds: float) -> String:
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]
