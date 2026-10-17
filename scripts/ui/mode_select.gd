class_name ModeSelect
extends Control
## Que clase de run se juega: con arsenal o con un arma sola.
##
## Va antes de elegir arena porque cambia mas la run que el piso: en ARSENAL la
## tienda vende armas y cada una se compra; en ONE GUN el arma se elige aca y es
## la de las diez oleadas, y la tienda solo vende mejoras.
##
## Armado por codigo, como `CreditsPanel`: son dos botones y una fila de armas que
## sale del catalogo de la tienda, y un arma nueva en el catalogo aparece aca sin
## tocar una escena.

signal mode_chosen(mode: GameManager.Mode, weapon_id: StringName)
signal closed()

const CATALOG_PATH: String = "res://data/economy/shop_catalog.tres"

var _arsenal_button: Button
var _single_button: Button
var _weapon_row: HBoxContainer
var _weapon_buttons: Array[Button] = []
var _play_button: Button
var _back_button: Button
var _armory_button: Button
var _armory: ArmoryPanel
## Un codigo compartido (o solo la semilla). Vacio: semilla nueva. Ver RunSeed.
var _seed_input: LineEdit
var _seed_status: Label

var _mode: GameManager.Mode = GameManager.Mode.ARSENAL
var _weapon_id: StringName = &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	# Anclas y offsets: con solo las anclas Godot conserva el rect de 0x0 con que
	# nace el nodo, y el panel "centrado" queda en la esquina superior izquierda.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _input(event: InputEvent) -> void:
	if not visible or (_armory != null and _armory.visible):
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# Public API

## Abre con la ultima eleccion marcada: "otra run" casi siempre es la misma.
func open() -> void:
	_mode = GameManager.run_mode
	_weapon_id = GameManager.run_weapon_id
	# La semilla fija sobrevive a "reiniciar", pero volver al menu es empezar de
	# nuevo: el campo muestra la que hay, y vaciarlo vuelve a sortear.
	_seed_input.text = RunSeed.encode_seed(GameManager.run_fixed_seed) \
		if GameManager.run_fixed_seed > 0 else ""
	_seed_status.text = ""
	if _weapon_id == &"" and not _weapon_buttons.is_empty():
		_weapon_id = StringName(_weapon_buttons[0].get_meta(&"weapon_id"))
	_refresh()
	visible = true
	_play_button.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func choose(mode: GameManager.Mode, weapon_id: StringName = &"") -> void:
	_mode = mode
	if weapon_id != &"":
		_weapon_id = weapon_id
	_refresh()


func get_mode() -> GameManager.Mode:
	return _mode


func get_weapon_id() -> StringName:
	return _weapon_id


func confirm() -> void:
	if not apply_seed_text(_seed_input.text):
		_seed_status.text = "That code is not valid. Clear it to play a fresh run."
		return
	visible = false
	mode_chosen.emit(_mode, _weapon_id if _mode == GameManager.Mode.SINGLE_WEAPON else &"")


## Lee el codigo del campo y deja la semilla fija en GameManager. Un codigo con
## modo cambia tambien el modo y el arma: jugar el codigo de otro es jugar su run.
## Devuelve false si el texto no es un codigo.
func apply_seed_text(text: String) -> bool:
	if text.strip_edges() == "":
		GameManager.set_run_seed(0)
		return true
	var parsed: Dictionary = RunSeed.parse_code(text)
	if parsed.is_empty():
		return false
	var mode: int = int(parsed["mode"])
	if mode >= 0:
		choose(mode as GameManager.Mode, StringName(parsed["weapon_id"]))
	GameManager.set_run_seed(int(parsed["seed"]))
	return true


# Private

func _build() -> void:
	theme = load("res://ui/mayhem_theme.tres") as Theme
	var dim := ColorRect.new()
	dim.color = Color(Tokens.VOID, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"HUDPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(760.0, 0.0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	margin.add_child(layout)

	var title := Label.new()
	title.text = "CHOOSE A MODE"
	title.add_theme_font_size_override("font_size", 30)
	layout.add_child(title)

	_arsenal_button = _mode_button("ARSENAL",
		"Start with the pistol. The shop sells every other weapon - each one has a price.",
		GameManager.Mode.ARSENAL)
	layout.add_child(_arsenal_button)
	_single_button = _mode_button("ONE GUN",
		"Pick a weapon now and keep it for all ten waves. The shop sells upgrades only.",
		GameManager.Mode.SINGLE_WEAPON)
	layout.add_child(_single_button)

	_weapon_row = HBoxContainer.new()
	_weapon_row.add_theme_constant_override("separation", 10)
	layout.add_child(_weapon_row)
	var catalog: ShopCatalog = load(CATALOG_PATH) as ShopCatalog
	if catalog != null:
		for weapon: WeaponData in catalog.weapons:
			if weapon == null:
				continue
			var button := Button.new()
			button.toggle_mode = true
			button.text = weapon.display_name
			button.tooltip_text = "Play the whole run with the %s." % weapon.display_name
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.set_meta(&"weapon_id", weapon.id)
			var id: StringName = weapon.id
			button.pressed.connect(func() -> void:
				choose(GameManager.Mode.SINGLE_WEAPON, id))
			_weapon_row.add_child(button)
			_weapon_buttons.append(button)

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 10)
	layout.add_child(seed_row)
	var seed_label := Label.new()
	seed_label.theme_type_variation = &"HUDLabel"
	seed_label.text = "RUN CODE"
	seed_row.add_child(seed_label)
	_seed_input = LineEdit.new()
	_seed_input.placeholder_text = "Paste a friend's code to play their run - leave empty for a new one"
	_seed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_input.text_submitted.connect(func(_text: String) -> void: confirm())
	seed_row.add_child(_seed_input)
	_seed_status = Label.new()
	_seed_status.theme_type_variation = &"HUDLabel"
	_seed_status.add_theme_color_override("font_color", Tokens.HAZARD)
	layout.add_child(_seed_status)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 12)
	layout.add_child(footer)
	_armory_button = Button.new()
	_armory_button.text = "Armory"
	_armory_button.tooltip_text = "Weapon mastery and the attachments it unlocks."
	_armory_button.pressed.connect(_open_armory)
	footer.add_child(_armory_button)
	_back_button = Button.new()
	_back_button.text = "Back"
	_back_button.pressed.connect(close)
	footer.add_child(_back_button)
	_play_button = Button.new()
	_play_button.text = "Play"
	_play_button.pressed.connect(confirm)
	footer.add_child(_play_button)


func _open_armory() -> void:
	if _armory == null:
		_armory = ArmoryPanel.new()
		_armory.name = "Armory"
		add_child(_armory)
		_armory.closed.connect(func() -> void: _armory_button.grab_focus())
	_armory.open()


func _mode_button(caption: String, detail: String, mode: GameManager.Mode) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.text = "%s   -   %s" % [caption, detail]
	button.tooltip_text = detail
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size = Vector2(0.0, 56.0)
	button.pressed.connect(func() -> void: choose(mode))
	return button


func _refresh() -> void:
	var single: bool = _mode == GameManager.Mode.SINGLE_WEAPON
	_arsenal_button.button_pressed = not single
	_single_button.button_pressed = single
	_weapon_row.visible = single
	for button: Button in _weapon_buttons:
		button.button_pressed = StringName(button.get_meta(&"weapon_id")) == _weapon_id
