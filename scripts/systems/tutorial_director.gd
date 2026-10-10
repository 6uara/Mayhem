class_name TutorialDirector
extends Node
## El tutorial de arranque: antes de la primera oleada, un recorrido corto por lo
## que el juego tiene - moverse, saltar, deslizar, dash, gancho, disparar,
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


func _ready() -> void:
	if catalog == null and ResourceLoader.exists(STEPS_PATH):
		catalog = load(STEPS_PATH) as TutorialStepCatalog
	if catalog != null:
		_steps = catalog.steps
	EventBus.dash_used.connect(_on_goal.bind(&"dash").unbind(1))
	EventBus.grapple_started.connect(_on_goal.bind(&"grapple").unbind(1))
	EventBus.weapon_fired.connect(_on_goal.bind(&"fire").unbind(1))
	EventBus.weapon_reloaded.connect(_on_goal.bind(&"reload").unbind(1))
	EventBus.weapon_ads_changed.connect(_on_ads_changed)


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


## El texto de un paso con cada `{accion}` cambiada por su tecla actual.
static func resolve_text(text: String) -> String:
	var out: String = text
	if out.contains("{move}"):
		var keys: PackedStringArray = PackedStringArray()
		for action: StringName in [&"move_forward", &"move_left", &"move_back", &"move_right"]:
			keys.append(TutorialHintManager.key_label(action))
		out = out.replace("{move}", "".join(keys))
	var regex := RegEx.new()
	regex.compile("\\{([a-z_]+)\\}")
	for found: RegExMatch in regex.search_all(out):
		var action := StringName(found.get_string(1))
		if InputMap.has_action(action):
			out = out.replace(found.get_string(0), TutorialHintManager.key_label(action))
	return out


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
	TutorialHintManager.show_tutorial_step(step.title, resolve_text(step.text),
		_index, _steps.size(), step.goal == &"")


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
	TutorialHintManager.end_tutorial(self)
	if not skipped:
		NarratorManager.say(&"tutorial_done")
	finished.emit(skipped)
