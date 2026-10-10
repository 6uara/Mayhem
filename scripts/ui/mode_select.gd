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

var _mode: GameManager.Mode = GameManager.Mode.ARSENAL
var _weapon_id: StringName = &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# Public API

## Abre con la ultima eleccion marcada: "otra run" casi siempre es la misma.
func open() -> void:
	_mode = GameManager.run_mode
	_weapon_id = GameManager.run_weapon_id
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
	visible = false
	mode_chosen.emit(_mode, _weapon_id if _mode == GameManager.Mode.SINGLE_WEAPON else &"")


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

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 12)
	layout.add_child(footer)
	_back_button = Button.new()
	_back_button.text = "Back"
	_back_button.pressed.connect(close)
	footer.add_child(_back_button)
	_play_button = Button.new()
	_play_button.text = "Play"
	_play_button.pressed.connect(confirm)
	footer.add_child(_play_button)


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
