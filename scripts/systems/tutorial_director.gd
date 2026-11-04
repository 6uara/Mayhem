class_name TutorialDirector
extends Node
## El tutorial de arranque: antes de la primera oleada, un recorrido corto por lo
## que el juego tiene - moverse, saltar, deslizar, la picada, gancho, disparar,
## recargar, los colores, el estilo y la tienda.
##
## La partida no empieza hasta que termina: `MatchDirector` espera `finished`
## antes de abrir la primera oleada. Se saltea con la tecla de `skip_tutorial` o
## desde el menu de pausa, y una vez terminado (o salteado) no vuelve a aparecer
## hasta que se borren los hints desde opciones.
##
## Tiene que ser rapido: los pasos de accion terminan apenas el jugador hace la
## cosa, y ninguno puede trabar a nadie - cada uno tiene un tope de tiempo y los
## que necesitan algo de la arena (anclas para el gancho) se saltean si no esta.
##
## Los textos son datos (`TutorialStep`). Lo que muestra la HUD pasa por
## `TutorialHintManager`, que es lo que la HUD ya escuchaba para los hints.

signal finished(skipped: bool)

const STEPS_PATH: String = "res://data/tutorial/tutorial_steps.tres"
## Se guarda como un hint visto: mismo archivo, misma forma de olvidarlo (el boton
## de opciones que vuelve a mostrar los hints tambien vuelve a mostrar esto).
const COMPLETED_ID: StringName = &"__tutorial_complete"
## Metros que hay que caminar para dar por aprendido el movimiento.
const MOVE_DISTANCE: float = 3.0
## Pausa entre un paso cumplido y el siguiente, para que se vea que se cumplio.
const STEP_GAP: float = 0.6

@export var catalog: TutorialStepCatalog

var is_running: bool = false

var _steps: Array[TutorialStep] = []
var _index: int = -1
var _elapsed: float = 0.0
## Segundos que faltan para pasar al siguiente despues de cumplir uno. Negativo
## mientras el paso actual sigue abierto.
var _gap_left: float = -1.0
var _player: Player
var _move_origin: Vector3 = Vector3.ZERO
var _key_ready: bool = true
var _nudged: bool = false


func _ready() -> void:
	if catalog == null and ResourceLoader.exists(STEPS_PATH):
		catalog = load(STEPS_PATH) as TutorialStepCatalog
	if catalog != null:
		_steps = catalog.steps
	EventBus.fast_fall_landed.connect(_on_goal.bind(&"fast_fall"))
	EventBus.grapple_started.connect(_on_goal.bind(&"grapple").unbind(1))
	EventBus.weapon_fired.connect(_on_goal.bind(&"fire").unbind(1))
	EventBus.weapon_reloaded.connect(_on_goal.bind(&"reload").unbind(1))
	EventBus.weapon_ads_changed.connect(_on_ads_changed)
	# Un rebind desde la pausa, o agarrar el joystick: el paso se vuelve a escribir.
	EventBus.settings_applied.connect(_show_current_step)
	TutorialHintManager.input_device_changed.connect(_show_current_step.unbind(1))


func _exit_tree() -> void:
	if is_running:
		TutorialHintManager.end_tutorial(self)


func _unhandled_input(event: InputEvent) -> void:
	if is_running and event.is_action_pressed(&"skip_tutorial"):
		skip()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_running:
		return
	if _gap_left >= 0.0:
		_gap_left -= delta
		if _gap_left < 0.0:
			_advance()
		return
	_elapsed += delta
	var step: TutorialStep = current_step()
	if step == null:
		return
	if step.goal == &"":
		if _elapsed >= step.duration:
			_advance()
		return
	if step.goal == &"move" and _moved_enough():
		_complete_step()
		return
	_tick_guidance(step)
	if step.max_time > 0.0 and _elapsed >= step.max_time:
		_advance()


# Public API

static func is_completed() -> bool:
	return SaveManager.has_seen_hint(COMPLETED_ID)


func should_run() -> bool:
	return not is_completed() and not _steps.is_empty()


## Arranca el recorrido. Si no corresponde, termina en el acto, asi quien espera
## `finished` no tiene que preguntar antes.
func begin() -> void:
	if not should_run():
		finished.emit(false)
		return
	is_running = true
	TutorialHintManager.begin_tutorial(self)
	_bind_player()
	_index = -1
	_advance()


func skip() -> void:
	if is_running:
		_finish(true)


func current_step() -> TutorialStep:
	return _steps[_index] if _index >= 0 and _index < _steps.size() else null


func get_step_index() -> int:
	return _index


func get_step_count() -> int:
	return _steps.size()


## El texto de un paso con cada `{accion}` cambiada por su tecla actual, en texto
## plano: sin marcas de color.
static func resolve_text(text: String) -> String:
	return _substitute_keys(_strip_colors(text), "%s")


## Lo mismo para la HUD, en BBCode: las teclas resaltadas y los colores pintados.
static func resolve_rich_text(text: String) -> String:
	var key_format: String = "[color=#%s]%%s[/color]" % Tokens.PLAYER.to_html(false)
	var out: String = _substitute_keys(text, key_format)
	var colors: Dictionary = _text_colors()
	for tag: String in colors:
		var tint: Color = colors[tag]
		out = out.replace("[%s]" % tag, "[color=#%s]" % tint.to_html(false))
		out = out.replace("[/%s]" % tag, "[/color]")
	return out


## Las teclas que nombra un texto, en orden y sin repetir. `move` son las cuatro.
static func actions_in(text: String) -> Array[StringName]:
	var actions: Array[StringName] = []
	for found: RegExMatch in _placeholder_regex().search_all(text):
		var action := StringName(found.get_string(1))
		if not actions.has(action) and (action == &"move" or InputMap.has_action(action)):
			actions.append(action)
	return actions


## Los colores que un texto puede nombrar. Ver `TutorialStep.text`.
static func _text_colors() -> Dictionary:
	return {
		"player": Tokens.WORLD_TRAVERSAL, "grapple": Tokens.WORLD_GRAPPLE,
		"hazard": Tokens.WORLD_HAZARD, "reward": Tokens.WORLD_PICKUP, "spawn": Tokens.SPAWN,
	}


static func _substitute_keys(text: String, key_format: String) -> String:
	var out: String = text
	if out.contains("{move}"):
		var keys: PackedStringArray = PackedStringArray()
		for action: StringName in TutorialKeys.MOVE_ACTIONS:
			var label: String = TutorialHintManager.key_label(action)
			# Con el joystick las cuatro son "Left Stick".
			if not keys.has(label):
				keys.append(label)
		out = out.replace("{move}", key_format % "".join(keys))
	for found: RegExMatch in _placeholder_regex().search_all(out):
		var action := StringName(found.get_string(1))
		if InputMap.has_action(action):
			out = out.replace(found.get_string(0), key_format % TutorialHintManager.key_label(action))
	return out


static func _strip_colors(text: String) -> String:
	var out: String = text
	for tag: String in _text_colors():
		out = out.replace("[%s]" % tag, "").replace("[/%s]" % tag, "")
	return out


static func _placeholder_regex() -> RegEx:
	var regex := RegEx.new()
	regex.compile("\\{([a-z_0-9]+)\\}")
	return regex


# Private

func _bind_player() -> void:
	_player = Players.local() as Player
	if _player != null:
		_move_origin = _player.global_position
		if _player.movement != null:
			if not _player.movement.jumped.is_connected(_on_jumped):
				_player.movement.jumped.connect(_on_jumped)
			if not _player.movement.state_changed.is_connected(_on_movement_state):
				_player.movement.state_changed.connect(_on_movement_state)


## Lo que guia sin esperar: si la tecla ya sirve, y la ayuda para quien no le sale.
func _tick_guidance(step: TutorialStep) -> void:
	var key_ready: bool = _is_key_ready(step)
	if key_ready != _key_ready:
		_key_ready = key_ready
		TutorialHintManager.set_tutorial_key_ready(key_ready)
	if not _nudged and step.nudge != "" and _elapsed >= step.nudge_after:
		_nudged = true
		TutorialHintManager.nudge_tutorial(resolve_rich_text(step.nudge))


## Sin jugador dice que si: mejor una tecla encendida de mas que un paso sin tecla.
func _is_key_ready(step: TutorialStep) -> bool:
	if _player == null or not is_instance_valid(_player):
		return true
	match step.ready_when:
		&"running":
			if _player.movement == null:
				return true
			var horizontal := Vector2(_player.velocity.x, _player.velocity.z)
			return horizontal.length() >= _player.movement.slide_min_speed
		&"airborne":
			return _player.movement == null \
				or _player.movement.state == MovementComponent.State.AIRBORNE
		&"anchor_in_range":
			return _player.grapple == null or _player.grapple.is_anchor_in_range
	return true


## El nodo del grupo mas cercano al jugador, o null.
func _waypoint_for(step: TutorialStep) -> Node3D:
	if step.waypoint_group == &"" or not is_inside_tree():
		return null
	var nearest: Node3D = null
	var best: float = INF
	for node: Node in get_tree().get_nodes_in_group(step.waypoint_group):
		var candidate := node as Node3D
		if candidate == null:
			continue
		var distance: float = 0.0
		if _player != null and is_instance_valid(_player):
			distance = _player.global_position.distance_squared_to(candidate.global_position)
		if distance < best:
			best = distance
			nearest = candidate
	return nearest


func _on_ads_changed(is_ads: bool) -> void:
	if is_ads:
		_on_goal(&"ads")


func _on_jumped() -> void:
	_on_goal(&"jump")


func _on_movement_state(state: MovementComponent.State) -> void:
	if state == MovementComponent.State.SLIDING:
		_on_goal(&"slide")


func _on_goal(goal: StringName) -> void:
	if not is_running or _gap_left >= 0.0:
		return
	var step: TutorialStep = current_step()
	if step != null and step.goal == goal:
		_complete_step()


func _moved_enough() -> bool:
	if _player == null or not is_instance_valid(_player):
		_bind_player()
		return false
	var offset: Vector3 = _player.global_position - _move_origin
	return Vector2(offset.x, offset.z).length() >= MOVE_DISTANCE


func _complete_step() -> void:
	var step: TutorialStep = current_step()
	if step != null and step.teaches_hint != &"":
		SaveManager.mark_hint_seen(step.teaches_hint)
	TutorialHintManager.complete_tutorial_step()
	TutorialHintManager.set_tutorial_waypoint(null)
	_gap_left = STEP_GAP


func _advance() -> void:
	_gap_left = -1.0
	_elapsed = 0.0
	_index += 1
	while _index < _steps.size() and not _step_applies(_steps[_index]):
		_index += 1
	if _index >= _steps.size():
		_finish(false)
		return
	var step: TutorialStep = _steps[_index]
	if step.goal == &"move" and _player != null and is_instance_valid(_player):
		_move_origin = _player.global_position
	_nudged = false
	_key_ready = _is_key_ready(step)
	_show_current_step()
	TutorialHintManager.set_tutorial_waypoint(_waypoint_for(step))


func _show_current_step() -> void:
	var step: TutorialStep = current_step()
	# En la pausa entre pasos el cumplido ya esta en pantalla: no se le borra.
	if not is_running or step == null or _gap_left >= 0.0:
		return
	var text: String = step.nudge if _nudged else step.text
	TutorialHintManager.show_tutorial_step(step.title, resolve_rich_text(text), _index,
		_steps.size(), step.goal == &"", actions_in(step.text), step.setup_action, _key_ready)


func _step_applies(step: TutorialStep) -> bool:
	if step == null:
		return false
	if step.requires_group != &"" and is_inside_tree() \
			and get_tree().get_nodes_in_group(step.requires_group).is_empty():
		return false
	return true


func _finish(skipped: bool) -> void:
	is_running = false
	_index = -1
	SaveManager.mark_hint_seen(COMPLETED_ID)
	TutorialHintManager.set_tutorial_waypoint(null)
	TutorialHintManager.end_tutorial(self)
	if not skipped:
		NarratorManager.say(&"tutorial_done")
	finished.emit(skipped)
