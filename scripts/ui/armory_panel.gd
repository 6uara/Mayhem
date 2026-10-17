class_name ArmoryPanel
extends Control
## La Armeria: el nivel de maestria de cada arma y los attachments que desbloqueo,
## para ponerse o sacarse antes de la run. Ver Armory.
##
## Armado por codigo, como ModeSelect, que es desde donde se abre: una fila por
## arma del catalogo de la tienda y una ficha por attachment, asi que un arma o un
## attachment nuevo en los datos aparece aca sin tocar una escena.

signal closed()

const SHOP_CATALOG_PATH: String = "res://data/economy/shop_catalog.tres"

var _rows: VBoxContainer
var _back_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	# Anclas y offsets, como ModeSelect: solo las anclas lo dejan en 0x0.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	# Solo los estados, no la grilla entera: rearmarla en medio del `toggled` que
	# la disparo le saca el foco al boton, y con joystick eso es perderse.
	Armory.changed.connect(_sync_states)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# Public API

func open() -> void:
	_refresh()
	visible = true
	_back_button.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## El texto de la fila de un arma. Publico para las pruebas.
static func describe_weapon(weapon: WeaponData) -> String:
	var level: int = Armory.get_level(weapon.id)
	var next: int = Armory.get_next_threshold(weapon.id)
	var progress: String = "MAX" if next < 0 else "%d / %d XP" % [Armory.get_xp(weapon.id), next]
	return "%s   LEVEL %d/%d   %s" % [weapon.display_name.to_upper(), level,
		Armory.catalog.max_level(), progress]


# Private

func _build() -> void:
	theme = load("res://ui/mayhem_theme.tres") as Theme
	var dim := ColorRect.new()
	dim.color = Color(Tokens.VOID, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"HUDPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(980.0, 0.0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	margin.add_child(layout)

	var title := Label.new()
	title.text = "ARMORY"
	title.add_theme_font_size_override("font_size", 30)
	layout.add_child(title)

	var intro := Label.new()
	intro.theme_type_variation = &"HUDLabel"
	intro.text = "Kills, style and cleared waves level up the weapon you are holding. " \
		+ "Each level unlocks an attachment. What you equip here goes into every run - " \
		+ "every attachment gives something and costs something."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(900.0, 0.0)
	layout.add_child(intro)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 12)
	layout.add_child(_rows)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	layout.add_child(footer)
	_back_button = Button.new()
	_back_button.text = "Back"
	_back_button.pressed.connect(close)
	footer.add_child(_back_button)


func _refresh() -> void:
	if _rows == null:
		return
	for child: Node in _rows.get_children():
		child.queue_free()
	var catalog := load(SHOP_CATALOG_PATH) as ShopCatalog
	if catalog == null:
		return
	for weapon: WeaponData in catalog.weapons:
		if weapon == null:
			continue
		var header := Label.new()
		header.theme_type_variation = &"HUDLabel"
		header.add_theme_color_override("font_color", Tokens.PLAYER)
		header.text = describe_weapon(weapon)
		_rows.add_child(header)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_rows.add_child(row)
		for attachment: AttachmentData in Armory.get_attachments(weapon.id):
			row.add_child(_attachment_button(attachment))


func _sync_states() -> void:
	if _rows == null:
		return
	for row: Node in _rows.get_children():
		for child: Node in row.get_children():
			var button := child as CheckButton
			if button == null or not button.has_meta(&"attachment_id"):
				continue
			var attachment: AttachmentData = Armory.catalog.find(
				StringName(button.get_meta(&"attachment_id")))
			button.set_pressed_no_signal(Armory.is_equipped(attachment))


func _attachment_button(attachment: AttachmentData) -> Button:
	var unlocked: bool = Armory.is_unlocked(attachment)
	var button := CheckButton.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0.0, 64.0)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var slot: String = AttachmentData.slot_label(attachment.slot)
	if unlocked:
		button.text = "%s  %s\n%s" % [slot, attachment.display_name, attachment.description]
	else:
		button.text = "%s  %s\nLocked - reach level %d" % [slot, attachment.display_name,
			attachment.unlock_level]
	button.disabled = not unlocked
	button.set_pressed_no_signal(Armory.is_equipped(attachment))
	button.set_meta(&"attachment_id", attachment.id)
	button.toggled.connect(func(on: bool) -> void:
		Armory.set_equipped(attachment, on))
	return button
