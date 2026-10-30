class_name CodexPanel
extends Control
## El codex: una ficha por cada cosa del juego - armas, mejoras, gadgets,
## enemigos, reglas, bonos - con lo que hace y sus numeros.
##
## Existe porque el juego enseña casi todo en el momento, en una carta de la
## tienda o en un cartel de la HUD que dura tres segundos, y no habia donde
## volver a mirarlo con calma. Se abre desde el menu y desde la pausa: la pregunta
## "¿que hacia el Healer?" aparece en medio de una run.
##
## Todo visible desde el principio, sin entradas bloqueadas: es una referencia,
## no un coleccionable. Las fichas salen de `CodexCatalog`; esto solo las dibuja.
## Armado por codigo, como `ArmoryPanel`.

signal closed()

const PANEL_SIZE: Vector2 = Vector2(1120.0, 680.0)
const LIST_WIDTH: float = 300.0
const DETAIL_ICON: float = 56.0

var _sections: Array[Dictionary] = []
var _section_index: int = 0
var _tab_row: HBoxContainer
var _tab_buttons: Array[Button] = []
var _list: VBoxContainer
var _list_scroll: ScrollContainer
var _detail: VBoxContainer
var _back_button: Button
var _tab_group: ButtonGroup = ButtonGroup.new()
var _entry_group: ButtonGroup = ButtonGroup.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	# Anclas y offsets, como ModeSelect: solo las anclas lo dejan en 0x0.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sections = CodexCatalog.sections()
	_build()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	# Los hombros del joystick y Re Pag / Av Pag cambian de pestaña: con nueve,
	# llegar a la ultima con el foco seria cruzar todas las fichas de la primera.
	var step: int = 0
	if event.is_action_pressed("ui_page_up"):
		step = -1
	elif event.is_action_pressed("ui_page_down"):
		step = 1
	var joy := event as InputEventJoypadButton
	if joy != null and joy.pressed:
		if joy.button_index == JOY_BUTTON_LEFT_SHOULDER:
			step = -1
		elif joy.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			step = 1
	if step != 0 and not _sections.is_empty():
		show_section(wrapi(_section_index + step, 0, _sections.size()))
		get_viewport().set_input_as_handled()


# Public API

func open() -> void:
	visible = true
	show_section(_section_index)
	UiMotion.enter(get_node(^"Panel") as Control)


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func get_section_count() -> int:
	return _sections.size()


## Muestra la pestaña `index` con su primera ficha elegida y el foco en ella.
func show_section(index: int) -> void:
	if _sections.is_empty():
		return
	_section_index = clampi(index, 0, _sections.size() - 1)
	for i: int in _tab_buttons.size():
		_tab_buttons[i].set_pressed_no_signal(i == _section_index)
	for child: Node in _list.get_children():
		# free() y no queue_free(): la lista se rearma entera en el mismo frame, y
		# los botones viejos esperando al final del frame quedan colgados del foco.
		child.free()
	var entries: Array = _sections[_section_index]["entries"]
	var first: Button = null
	for entry: Dictionary in entries:
		var button: Button = _make_entry_button(entry)
		_list.add_child(button)
		if first == null:
			first = button
	_list_scroll.scroll_vertical = 0
	if first != null:
		first.button_pressed = true
		show_entry(entries[0])
		if visible:
			first.grab_focus()


## Dibuja una ficha en el lado derecho.
func show_entry(entry: Dictionary) -> void:
	for child: Node in _detail.get_children():
		# Ningun nodo de la ficha es el que emitio la señal que nos trajo aca.
		child.free()
	var accent: Color = entry["accent"]

	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 16)
	_detail.add_child(header)
	var icon: Control = _make_icon(entry, DETAIL_ICON)
	if icon != null:
		header.add_child(icon)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override(&"separation", 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	var tag := Label.new()
	tag.theme_type_variation = &"HUDLabel"
	tag.text = String(entry["tag"])
	tag.add_theme_color_override(&"font_color", accent)
	titles.add_child(tag)
	var title := Label.new()
	title.name = "EntryName"
	title.text = String(entry["name"])
	title.add_theme_font_size_override(&"font_size", 30)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(title)

	var body := Label.new()
	body.name = "EntryBody"
	body.text = String(entry["body"])
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override(&"font_color", Color(Tokens.TEXT, 0.9))
	_detail.add_child(body)

	var tip: String = String(entry.get("tip", ""))
	if not tip.is_empty():
		_detail.add_child(_make_tip(String(entry.get("tip_title", "")), tip, accent))

	var stats: Array = entry["stats"]
	if not stats.is_empty():
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override(&"h_separation", 24)
		grid.add_theme_constant_override(&"v_separation", 8)
		_detail.add_child(grid)
		for stat: Array in stats:
			var label := Label.new()
			label.theme_type_variation = &"HUDLabel"
			label.text = String(stat[0])
			label.custom_minimum_size = Vector2(190.0, 0.0)
			grid.add_child(label)
			var value := Label.new()
			value.text = String(stat[1])
			value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(value)


# Private

func _build() -> void:
	theme = load("res://ui/mayhem_theme.tres") as Theme
	var dim := ColorRect.new()
	dim.color = Color(Tokens.VOID, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.theme_type_variation = &"HUDPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = PANEL_SIZE
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override(&"separation", 14)
	margin.add_child(layout)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override(&"separation", 16)
	layout.add_child(title_row)
	var title := Label.new()
	title.text = "CODEX"
	title.add_theme_font_size_override(&"font_size", 30)
	title_row.add_child(title)
	var hint := Label.new()
	hint.theme_type_variation = &"HUDLabel"
	hint.text = "PG UP / PG DN  -  LB / RB  TO CHANGE TAB"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_row.add_child(hint)

	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override(&"separation", 6)
	layout.add_child(_tab_row)
	for i: int in _sections.size():
		var tab := Button.new()
		tab.toggle_mode = true
		tab.button_group = _tab_group
		tab.text = String(_sections[i]["title"])
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.tooltip_text = "%d entries" % (_sections[i]["entries"] as Array).size()
		var index: int = i
		tab.pressed.connect(func() -> void: show_section(index))
		_tab_row.add_child(tab)
		_tab_buttons.append(tab)

	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(body)

	_list_scroll = ScrollContainer.new()
	_list_scroll.custom_minimum_size = Vector2(LIST_WIDTH, 0.0)
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_list_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.add_child(_list)

	var divider := VSeparator.new()
	body.add_child(divider)

	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(detail_scroll)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override(&"separation", 18)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_detail)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	layout.add_child(footer)
	_back_button = Button.new()
	_back_button.text = "Back"
	_back_button.custom_minimum_size = Vector2(150.0, 44.0)
	_back_button.pressed.connect(close)
	footer.add_child(_back_button)


## Una fila de la lista. Elegirla con el foco ya muestra la ficha: con joystick
## no hay que apretar nada para leer, solo bajar.
func _make_entry_button(entry: Dictionary) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.button_group = _entry_group
	button.text = String(entry["name"])
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.custom_minimum_size = Vector2(0.0, 38.0)
	button.set_meta(&"entry_id", entry["id"])
	var select: Callable = func() -> void:
		button.set_pressed_no_signal(true)
		show_entry(entry)
	button.pressed.connect(select)
	button.focus_entered.connect(select)
	# El acento como raya a la izquierda: en la lista de enemigos el color es lo
	# primero que se reconoce, antes que el nombre.
	var rail := ColorRect.new()
	rail.color = entry["accent"]
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail.custom_minimum_size = Vector2(3.0, 0.0)
	rail.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	rail.offset_right = 3.0
	button.add_child(rail)
	return button


func _make_tip(heading: String, text: String, accent: Color) -> Control:
	var box := PanelContainer.new()
	var style := ChamferStyleBox.new()
	style.fill_color = Tokens.RAISED
	style.fill_alpha = 0.85
	style.border_color = Tokens.LINE
	style.border_width = 1.0
	style.chamfer = 12.0
	style.rail_width = 4.0
	style.rail_color = accent
	style.rail_side = SIDE_LEFT
	box.add_theme_stylebox_override(&"panel", style)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 18)
	margin.add_theme_constant_override(&"margin_top", 12)
	margin.add_theme_constant_override(&"margin_right", 16)
	margin.add_theme_constant_override(&"margin_bottom", 12)
	box.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 4)
	margin.add_child(column)
	if not heading.is_empty():
		var label := Label.new()
		label.theme_type_variation = &"HUDLabel"
		label.text = heading
		label.add_theme_color_override(&"font_color", accent)
		column.add_child(label)
	var body := Label.new()
	body.name = "TipBody"
	body.text = text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(body)
	return box


## El icono de una ficha: el del set dibujado si hay archivo, si no la geometria
## de `MayhemIcon`, y si no hay ninguno, nada.
func _make_icon(entry: Dictionary, box: float) -> Control:
	var accent: Color = entry["accent"]
	var group: StringName = entry["icon_group"]
	var id: StringName = entry["icon_id"]
	if group != &"" and IconSet.has(group, id):
		return IconSet.make(group, id, accent, box)
	var kind: MayhemIcon.Kind = entry["icon_kind"]
	if kind == MayhemIcon.Kind.NONE:
		return null
	var icon := MayhemIcon.new()
	icon.kind = kind
	icon.color = accent
	icon.custom_minimum_size = Vector2(box, box)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return icon
