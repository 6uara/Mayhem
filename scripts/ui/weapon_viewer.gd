extends Node3D
## Visor de armas: el arma y los brazos como los ve el jugador, con todo lo que
## decide como quedan en pantalla editable en vivo y un boton para guardarlo.
##
## Existe porque acomodar un viewmodel es mirar: el tamaño del arma contra la
## mano, donde cae en la pantalla, si la mano agarra la empuñadura o flota al
## lado. Cada numero de WeaponData que importa para eso tiene su campo aca, y
## cambiarlo rehace el arma en el acto.
##
## Lo que se ve es lo del juego: el `ViewmodelRig` de verdad (su mundo, su camara,
## su FOV y sus luces) y un `WeaponComponent` de verdad montado en el, con la
## arena por defecto atras. La recarga es la del componente, a su velocidad real.
##
## Se abre desde el menu principal (solo en builds de debug) o con `weapons` en
## la consola de desarrollo. Tambien corre suelto con F6 en el editor.

const RIG_SCENE: PackedScene = preload("res://scenes/player/viewmodel_rig.tscn")
const THEME: Theme = preload("res://ui/mayhem_theme.tres")
const DATA_DIR: String = "res://data/weapons"
const ARENA_PATH: String = "res://data/arenas/default_arena.tres"
const CATALOG_PATH: String = "res://data/arena_pieces/default_catalog.tres"
## Donde se para el ojo en la arena de fondo: al centro, a la altura del jugador.
const EYE_IN_ARENA := Vector3(30.0, 2.5, 52.0)
const LOOK_IN_ARENA := Vector3(40.0, 2.2, 30.0)

## Paso de cada campo: metros, factor de escala y grados.
const METRE_STEP: float = 0.005
const SCALE_STEP: float = 0.01
const DEGREE_STEP: float = 1.0

## Las vistas de afuera, relativas a la camara del rig: de costado y de arriba,
## para ver si la mano toca el arma o la atraviesa.
const VIEWS: Dictionary = {
	"Jugador": [],
	"Costado": [Vector3(0.9, -0.1, -0.35), Vector3(0.1, -0.15, -0.4)],
	"Arriba": [Vector3(0.1, 0.8, -0.4), Vector3(0.1, -0.15, -0.4)],
}

## Campos: [titulo de la seccion, propiedad de WeaponData, etiqueta, tipo, paso].
const FIELDS: Array = [
	["ARMA", &"viewmodel_scale", "Escala", TYPE_FLOAT, SCALE_STEP],
	["ARMA", &"viewmodel_offset", "Posicion", TYPE_VECTOR3, METRE_STEP],
	["ARMA", &"viewmodel_rotation_degrees", "Giro", TYPE_VECTOR3, DEGREE_STEP],
	["MANOS", &"viewmodel_grip_offset", "Mano derecha", TYPE_VECTOR3, METRE_STEP],
	["MANOS", &"viewmodel_support_offset", "Mano izquierda", TYPE_VECTOR3, METRE_STEP],
	["MANOS", &"viewmodel_grip_rotation_degrees", "Giro derecha", TYPE_VECTOR3, DEGREE_STEP],
	["MANOS", &"viewmodel_support_rotation_degrees", "Giro izquierda", TYPE_VECTOR3, DEGREE_STEP],
	["RECARGA", &"reload_tilt_degrees", "Inclinacion", TYPE_VECTOR3, DEGREE_STEP],
]

var _weapons: Array[WeaponData] = []
var _data: WeaponData
var _rig: ViewmodelRig
var _weapon: WeaponComponent
var _outside_camera: Camera3D
var _view: String = "Jugador"

var _weapon_list: VBoxContainer
var _editors: Dictionary = {}  # StringName -> Array[SpinBox]
var _status: Label
var _syncing: bool = false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_backdrop()
	_build_rig()
	_build_ui()
	_weapons = _load_weapons()
	for data: WeaponData in _weapons:
		var button := Button.new()
		button.text = data.display_name.to_upper()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_show_weapon.bind(data))
		_weapon_list.add_child(button)
	if not _weapons.is_empty():
		_show_weapon(_weapons[0])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


# Weapon

func _show_weapon(data: WeaponData) -> void:
	_data = data
	_sync_editors()
	_rebuild_weapon()
	_set_status("%s  -  %s" % [data.display_name, data.resource_path.get_file()])


## Arma el arma de nuevo con los valores de ahora. Mas simple y mas fiel que
## mover lo que ya esta: el componente calcula la boca del cañon, la caja y el
## agarre al montarse, igual que en partida.
func _rebuild_weapon() -> void:
	if _weapon != null:
		_weapon.queue_free()
		for child: Node in _rig.get_slot_parent().get_children():
			child.queue_free()
	if _data == null:
		return
	_weapon = WeaponComponent.new()
	_weapon.data = _data
	_weapon.viewmodel_parent = _rig.get_slot_parent()
	_weapon.aim_node = _weapon
	add_child(_weapon)


func _on_field_changed(_value: float, property: StringName) -> void:
	if _syncing or _data == null:
		return
	var boxes: Array = _editors[property]
	if boxes.size() == 1:
		_data.set(property, (boxes[0] as SpinBox).value)
	else:
		_data.set(property, Vector3((boxes[0] as SpinBox).value,
			(boxes[1] as SpinBox).value, (boxes[2] as SpinBox).value))
	_rebuild_weapon()
	_set_status("%s  -  sin guardar" % _data.display_name)


func _sync_editors() -> void:
	_syncing = true
	for property: StringName in _editors:
		var boxes: Array = _editors[property]
		var value: Variant = _data.get(property)
		if boxes.size() == 1:
			(boxes[0] as SpinBox).value = float(value)
		else:
			var vector: Vector3 = value
			for axis: int in 3:
				(boxes[axis] as SpinBox).value = vector[axis]
	_syncing = false


func _on_reload_pressed() -> void:
	if _weapon == null:
		return
	_weapon.reset()
	_weapon._ammo = 0
	_weapon.try_reload()


## Esconder y mostrar el arma es lo que hace el cambio de arma en partida, y es
## lo que dispara la animacion de sacarla.
func _on_equip_pressed() -> void:
	if _weapon == null:
		return
	_weapon.visible = false
	_weapon.visible = true


func _on_save_pressed() -> void:
	if _data == null:
		return
	var error: Error = ResourceSaver.save(_data, _data.resource_path)
	if error == OK:
		_set_status("Guardado en %s" % _data.resource_path)
	else:
		_set_status("No se pudo guardar (%s)" % error_string(error))


## Vuelve a leer el .tres del disco, descartando lo que no se guardo.
func _on_revert_pressed() -> void:
	if _data == null:
		return
	var path: String = _data.resource_path
	var fresh := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as WeaponData
	var index: int = _weapons.find(_data)
	if fresh == null or index < 0:
		return
	_weapons[index] = fresh
	var button := _weapon_list.get_child(index) as Button
	for connection: Dictionary in button.pressed.get_connections():
		button.pressed.disconnect(connection["callable"])
	button.pressed.connect(_show_weapon.bind(fresh))
	_show_weapon(fresh)
	_set_status("%s  -  vuelto a lo guardado" % fresh.display_name)


func _on_view_selected(index: int, options: OptionButton) -> void:
	_view = options.get_item_text(index)
	var placement: Array = VIEWS[_view]
	if placement.is_empty():
		_rig.camera.current = true
		return
	var eye: Vector3 = _rig.camera.global_transform * (placement[0] as Vector3)
	var target: Vector3 = _rig.camera.global_transform * (placement[1] as Vector3)
	var up: Vector3 = Vector3.FORWARD if _view == "Arriba" else Vector3.UP
	_outside_camera.look_at_from_position(eye, target, up)
	_outside_camera.current = true


func _on_back_pressed() -> void:
	GameManager.return_to_menu()


func _load_weapons() -> Array[WeaponData]:
	var out: Array[WeaponData] = []
	for file: String in ResourceLoader.list_directory(DATA_DIR):
		if not file.ends_with(".tres"):
			continue
		var data := load("%s/%s" % [DATA_DIR, file]) as WeaponData
		if data != null and data.viewmodel != null:
			out.append(data)
	return out


# Scene

## La arena por defecto atras, vista desde donde estaria el jugador: el arma se
## juzga contra lo que va a tener detras, no contra un fondo liso.
func _build_backdrop() -> void:
	var arena := load(ARENA_PATH) as ArenaData
	var catalog := load(CATALOG_PATH) as PieceCatalog
	if arena != null and catalog != null:
		ArenaLoader.load_arena(arena, self, catalog)
	var eye := Camera3D.new()
	eye.fov = 90.0
	add_child(eye)
	eye.look_at_from_position(EYE_IN_ARENA, LOOK_IN_ARENA, Vector3.UP)
	eye.current = true


func _build_rig() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_rig = RIG_SCENE.instantiate() as ViewmodelRig
	layer.add_child(_rig)
	_outside_camera = Camera3D.new()
	_outside_camera.near = 0.01
	_outside_camera.fov = 50.0
	_rig.get_node(^"SubViewport").add_child(_outside_camera)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	var root := Control.new()
	root.theme = THEME
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# La mira al centro: el arma se acomoda contra ella.
	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override(&"font_size", 28)
	cross.add_theme_color_override(&"font_color", Tokens.TEXT)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(cross)

	var column := _column(_panel(root, 340.0))
	var title := Label.new()
	title.text = "ARMERIA"
	title.add_theme_font_size_override(&"font_size", 26)
	column.add_child(title)
	_weapon_list = VBoxContainer.new()
	_weapon_list.add_theme_constant_override(&"separation", 6)
	column.add_child(_weapon_list)

	var section: String = ""
	for field: Array in FIELDS:
		if field[0] != section:
			section = field[0]
			column.add_child(_section(section))
		column.add_child(_field_row(field[1], field[2], field[3], field[4]))

	var hint := Label.new()
	hint.theme_type_variation = &"HUDLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "Ejes de camara: X derecha, Y arriba, Z atras (adelante es negativo). " \
		+ "Las manos corrigen donde agarran, sobre lo que se mide de la malla."
	hint.add_theme_color_override(&"font_color", Tokens.MUTED)
	column.add_child(hint)

	column.add_child(_section("VER"))
	var views := OptionButton.new()
	for view: String in VIEWS:
		views.add_item(view)
	views.item_selected.connect(_on_view_selected.bind(views))
	column.add_child(views)
	var actions := HBoxContainer.new()
	for entry: Array in [["Recargar", _on_reload_pressed], ["Sacar", _on_equip_pressed]]:
		var button := Button.new()
		button.text = entry[0]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(entry[1])
		actions.add_child(button)
	column.add_child(actions)

	column.add_child(_section("ARCHIVO"))
	for entry: Array in [["Guardar en el .tres", _on_save_pressed],
			["Volver a lo guardado", _on_revert_pressed], ["Volver  [ESC]", _on_back_pressed]]:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(entry[1])
		column.add_child(button)
	_status = Label.new()
	_status.theme_type_variation = &"HUDLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)


func _field_row(property: StringName, text: String, type: int, step: float) -> Control:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.theme_type_variation = &"HUDLabel"
	label.text = text
	box.add_child(label)
	var row := HBoxContainer.new()
	box.add_child(row)
	var spins: Array[SpinBox] = []
	var count: int = 1 if type == TYPE_FLOAT else 3
	for axis: int in count:
		var spin := SpinBox.new()
		spin.step = step
		spin.min_value = -1000.0
		spin.max_value = 1000.0
		spin.allow_greater = true
		spin.allow_lesser = true
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if count == 3:
			spin.prefix = ["X", "Y", "Z"][axis]
		spin.value_changed.connect(_on_field_changed.bind(property))
		row.add_child(spin)
		spins.append(spin)
	_editors[property] = spins
	return box


func _panel(parent: Control, width: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"HUDPanel"
	parent.add_child(panel)
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_right = width
	return panel


func _column(panel: PanelContainer) -> VBoxContainer:
	var margin := MarginContainer.new()
	for side: String in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	panel.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	return column


func _section(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"HUDLabel"
	label.text = text
	label.add_theme_color_override(&"font_color", Tokens.REWARD)
	return label


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text
