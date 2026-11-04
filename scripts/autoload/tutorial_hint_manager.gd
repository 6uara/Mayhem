extends Node
## Shows a one-line HUD overlay the first time the player performs each core
## mechanic - move, jump, mantle, slide, fast fall, grapple, ADS, reload, first shop
## visit. Content lives in TutorialHint resources (data/tutorial/), never as
## string literals here.
##
## Deliberately NOT NarratorManager: the Host talks to the crowd, not the
## player (see Game Treatment) - a tutorial prompt is a neutral HUD overlay,
## never a Host line. "Seen" persists forever via SaveManager, independent of
## the leaderboard and of any run - there is no meta-progression here, just a
## courtesy that stops repeating once learned.
##
## MovementComponent lives on the player, which is recreated every run
## (GameManager swaps the whole scene) - this autoload is not, so it rebinds
## to the current player's MovementComponent whenever a run starts rather than
## connecting once at startup.

signal hint_shown(text: String, duration: float)
signal hint_hidden()
## El tutorial de arranque (TutorialDirector) pasa por aca para llegar a la HUD,
## que ya escuchaba a este autoload. `is_info` es un paso que pasa solo. `text` trae
## BBCode; `actions` son las teclas que nombra, en orden, y `setup_action` la que hay
## que apretar antes para que sirvan.
signal tutorial_step_shown(title: String, text: String, index: int, total: int, is_info: bool,
		actions: Array[StringName], setup_action: StringName, key_ready: bool)
signal tutorial_step_completed()
## La tecla que pide el paso ya sirve (o dejo de servir).
signal tutorial_key_ready_changed(key_ready: bool)
## El jugador lleva rato sin poder: una ayuda mas concreta. BBCode, como `text`.
signal tutorial_nudged(text: String)
## Lo que el paso pide buscar en la arena. Null lo saca.
signal tutorial_waypoint_changed(target: Node3D)
## Teclado y mouse, o joystick: lo que la pantalla tiene que nombrar cambio.
signal input_device_changed(uses_gamepad: bool)
signal tutorial_ended()

const CATALOG_PATH: String = "res://data/tutorial/tutorial_hints.tres"
## Hints waiting to be shown are dropped past this, rather than growing
## unbounded - if the player has ignored four mechanics' worth of hints
## already, a fifth queued behind them would show stale advice anyway.
const MAX_QUEUED: int = 4
## Cuanto hay que mover un stick o gatillo para que cuente como agarrar el joystick.
const STICK_WAKE: float = 0.5

var _hints_by_id: Dictionary = {}  # StringName -> TutorialHint
var _queue: Array[TutorialHint] = []
var _current: TutorialHint
var _time_left: float = 0.0
var _movement: MovementComponent
## El tutorial que esta corriendo, o null. Mientras corre, los hints de primera
## vez se callan: los dos usan la misma banda de la pantalla, y el tutorial ya
## esta enseñando lo mismo.
var _tutorial: Node
var _uses_gamepad: bool = false


func _ready() -> void:
	_load_catalog()
	EventBus.game_state_changed.connect(_on_game_state_changed)
	EventBus.fast_fall_landed.connect(_on_fast_fall_landed)
	EventBus.grapple_started.connect(_on_grapple_started)
	EventBus.weapon_reloaded.connect(_on_weapon_reloaded)
	EventBus.weapon_ads_changed.connect(_on_weapon_ads_changed)
	EventBus.shop_opened.connect(_on_shop_opened)
	_bind_player.call_deferred()


func _process(delta: float) -> void:
	if _current == null:
		_try_show_next()
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_finish_current()


## El ultimo dispositivo con el que se apreto algo. Sin el movimiento del mouse: un
## jugador de joystick que lo roza con la mano no quiere que cambie toda la pantalla.
## Sin el stick apenas movido, por la misma razon, y porque los sticks derivan.
func _input(event: InputEvent) -> void:
	var pad: bool = _uses_gamepad
	if event is InputEventKey or event is InputEventMouseButton:
		pad = false
	elif event is InputEventJoypadButton:
		pad = true
	elif event is InputEventJoypadMotion:
		pad = pad or absf((event as InputEventJoypadMotion).axis_value) >= STICK_WAKE
	if pad != _uses_gamepad:
		_uses_gamepad = pad
		input_device_changed.emit(pad)


# Signal handlers - EventBus

func _on_fast_fall_landed() -> void:
	_fire(&"fast_fall")


func _on_grapple_started(_anchor: Vector3) -> void:
	_fire(&"grapple")


func _on_weapon_reloaded(_weapon_id: StringName) -> void:
	_fire(&"reload")


func _on_weapon_ads_changed(is_ads: bool) -> void:
	if is_ads:
		_fire(&"ads")


func _on_shop_opened() -> void:
	_fire(&"shop")


## Fresh player scene per run - rebind rather than assume the old
## MovementComponent (now freed) is still good.
func _on_game_state_changed(new_state: int) -> void:
	if new_state == GameManager.State.PLAYING:
		_bind_player.call_deferred()


# Signal handlers - MovementComponent

func _on_movement_state_changed(new_state: MovementComponent.State) -> void:
	if new_state == MovementComponent.State.SLIDING:
		_fire(&"slide")


func _on_started_moving() -> void:
	_fire(&"move")


func _on_jumped() -> void:
	_fire(&"jump")


func _on_mantled() -> void:
	_fire(&"mantle")


# Private

func _load_catalog() -> void:
	_hints_by_id.clear()
	if not ResourceLoader.exists(CATALOG_PATH):
		return
	var catalog: TutorialHintCatalog = load(CATALOG_PATH)
	for hint: TutorialHint in catalog.hints:
		if hint != null:
			_hints_by_id[hint.id] = hint


func _bind_player() -> void:
	var player: Player = Players.local() as Player
	if player == null or player.movement == null or player.movement == _movement:
		return
	_movement = player.movement
	_movement.state_changed.connect(_on_movement_state_changed)
	_movement.started_moving.connect(_on_started_moving)
	_movement.jumped.connect(_on_jumped)
	_movement.mantled.connect(_on_mantled)


func _fire(id: StringName) -> void:
	if is_tutorial_running():
		return
	if SaveManager.has_seen_hint(id):
		return
	var hint: TutorialHint = _hints_by_id.get(id)
	if hint == null:
		return
	# Only a hint that actually made it onto the queue counts as seen. Marking
	# before this guard burned the "seen" flag on a hint that was then dropped -
	# and since the flag persists across runs, that hint was gone for good.
	if _queue.size() >= MAX_QUEUED:
		return
	SaveManager.mark_hint_seen(id)
	_queue.push_back(hint)


## Guards _current itself, not just the _process() caller - hints never
## overlap is a hard invariant, not an accident of who happens to call this.
func _try_show_next() -> void:
	if _current != null or _queue.is_empty():
		return
	_current = _queue.pop_front()
	_time_left = maxf(_current.duration, 0.1)
	hint_shown.emit(_resolve_text(_current), _time_left)


func _finish_current() -> void:
	_current = null
	hint_hidden.emit()


# Public API - tutorial de arranque

func begin_tutorial(tutorial: Node) -> void:
	_tutorial = tutorial
	_queue.clear()
	if _current != null:
		_finish_current()


func end_tutorial(tutorial: Node) -> void:
	if _tutorial != tutorial:
		return
	_tutorial = null
	tutorial_ended.emit()


func is_tutorial_running() -> bool:
	return _tutorial != null and is_instance_valid(_tutorial)


## Lo que llama el boton de la pausa. No sabe como se saltea: se lo pide al
## tutorial que este corriendo.
func skip_tutorial() -> void:
	if is_tutorial_running() and _tutorial.has_method(&"skip"):
		_tutorial.call(&"skip")


func show_tutorial_step(title: String, text: String, index: int, total: int, is_info: bool,
		actions: Array[StringName], setup_action: StringName, key_ready: bool) -> void:
	tutorial_step_shown.emit(title, text, index, total, is_info, actions, setup_action, key_ready)


func complete_tutorial_step() -> void:
	tutorial_step_completed.emit()


func set_tutorial_key_ready(key_ready: bool) -> void:
	tutorial_key_ready_changed.emit(key_ready)


func nudge_tutorial(text: String) -> void:
	tutorial_nudged.emit(text)


func set_tutorial_waypoint(target: Node3D) -> void:
	tutorial_waypoint_changed.emit(target)


func uses_gamepad() -> bool:
	return _uses_gamepad


## La tecla que tiene asignada `action` ahora mismo, como se escribe en pantalla.
func key_label(action: StringName) -> String:
	return _key_label(action)


## El evento de `action` que la pantalla tiene que nombrar: el del dispositivo en
## uso y, si en ese no tiene ninguno, el que tenga.
func prompt_event(action: StringName) -> InputEvent:
	var preferred: InputEvent = SettingsManager.get_gamepad_event(action) if _uses_gamepad \
		else SettingsManager.get_primary_event(action)
	if preferred != null or not InputMap.has_action(action):
		return preferred
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	return events[0] if not events.is_empty() else null


## Substitutes the live-bound key for `hint.action`'s first key event into the
## first "{action}" placeholder - a remapped key is never wrong, and a hint
## with no action (movement, the shop) passes its text through untouched.
func _resolve_text(hint: TutorialHint) -> String:
	if hint.action == &"" or not _text_has_placeholder(hint.text):
		return hint.text
	return hint.text.replace("{action}", _key_label(hint.action))


func _text_has_placeholder(text: String) -> bool:
	return text.find("{action}") >= 0


func _key_label(action: StringName) -> String:
	var event: InputEvent = prompt_event(action)
	return SettingsManager.describe_event(event) if event != null else "?"
