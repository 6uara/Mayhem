class_name TutorialKeys
extends HBoxContainer
## La fila de teclas de un paso del tutorial: las que nombra el texto y, si el
## paso necesita una preparacion, esa primero con una flecha: [SPACE] > [CTRL].
##
## La tecla que late es la que sirve *ahora*. Una tecla encendida que no hace nada
## enseña a desconfiar de la pantalla: la picada late recien en el aire, y el gancho
## recien con un ancla al alcance. Ver `TutorialStep.ready_when`.

## WASD como esta en el teclado. Con el joystick las cuatro son el mismo stick y
## queda una sola.
const MOVE_ACTIONS: Array[StringName] = [
	&"move_forward", &"move_left", &"move_back", &"move_right"]

var _setup_cap: KeyCap
## Las teclas que el paso pide, sin las que nombra de paso (apuntar, en el de tirar).
var _main_caps: Array[KeyCap] = []
var _caps: Array[KeyCap] = []
var _key_ready: bool = true


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_theme_constant_override("separation", Tokens.KEY_CAP_GROUP_GAP)


## `actions` en el orden del texto: la primera es la que el paso pide.
func show_actions(actions: Array[StringName], setup_action: StringName = &"",
		key_ready: bool = true) -> void:
	_clear()
	_key_ready = key_ready
	if setup_action != &"":
		_setup_cap = KeyCap.new().setup(setup_action)
		_caps.append(_setup_cap)
		add_child(_setup_cap)
		add_child(_arrow())
	for index: int in actions.size():
		var group: Array[KeyCap] = _add_group(actions[index])
		if index == 0:
			_main_caps = group
	visible = not _caps.is_empty()
	_apply_ready()


func set_key_ready(key_ready: bool) -> void:
	_key_ready = key_ready
	_apply_ready()


func mark_done() -> void:
	for cap: KeyCap in _main_caps:
		cap.mark_done()


func get_caps() -> Array[KeyCap]:
	return _caps


func get_main_caps() -> Array[KeyCap]:
	return _main_caps


func get_setup_cap() -> KeyCap:
	return _setup_cap


func _apply_ready() -> void:
	if _setup_cap != null:
		_setup_cap.is_asked = not _key_ready
	for cap: KeyCap in _main_caps:
		cap.is_asked = _key_ready


func _clear() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_setup_cap = null
	_main_caps = []
	_caps = []


func _add_group(action: StringName) -> Array[KeyCap]:
	var group: Array[KeyCap] = []
	if action != &"move":
		group.append(KeyCap.new().setup(action))
		add_child(group[0])
	elif TutorialHintManager.uses_gamepad():
		group.append(KeyCap.new().setup(MOVE_ACTIONS[0]))
		add_child(group[0])
	else:
		add_child(_move_grid(group))
	_caps.append_array(group)
	return group


## La T invertida: W arriba de S, con un hueco a cada lado.
func _move_grid(group: Array[KeyCap]) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", Tokens.KEY_CAP_GAP)
	grid.add_theme_constant_override("v_separation", Tokens.KEY_CAP_GAP)
	grid.add_child(_gap())
	for action: StringName in MOVE_ACTIONS:
		var cap: KeyCap = KeyCap.new().setup(action)
		group.append(cap)
		grid.add_child(cap)
		if action == &"move_forward":
			grid.add_child(_gap())
	return grid


func _gap() -> Control:
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


func _arrow() -> Label:
	var arrow := Label.new()
	arrow.theme_type_variation = &"HUDLabel"
	arrow.text = ">"
	return arrow
