extends Node
## Match state machine and run lifecycle. Knows nothing about UI layout.

enum State { MENU, PLAYING, SHOPPING, GAME_OVER }

const GAME_SCENE_PATH: String = "res://scenes/main/game.tscn"
const MENU_SCENE_PATH: String = "res://scenes/main/main_menu.tscn"
const TRANSITION_SCENE: PackedScene = preload("res://scenes/ui/scene_transition.tscn")

var state: State = State.MENU:
	set(value):
		if state == value:
			return
		state = value
		EventBus.game_state_changed.emit(int(value))

var is_paused: bool = false

var _run_start_time: float = 0.0
## GameManager's own child, not part of whatever scene is being replaced -
## survives every change_scene_to_file() call untouched. See
## scripts/ui/scene_transition.gd.
var _transition: SceneTransition


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.player_died.connect(_on_player_died)
	_transition = TRANSITION_SCENE.instantiate()
	add_child(_transition)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and state == State.PLAYING:
		toggle_pause()
		get_viewport().set_input_as_handled()


# Public API

func start_run() -> void:
	is_paused = false
	get_tree().paused = false
	_run_start_time = _now()
	state = State.PLAYING
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Must land the player back in a shooting state in under 2 seconds - the fade
## (SceneTransition.duration, each way) eats a fraction of that budget on
## purpose, short enough to leave the rest of it intact.
func restart_run() -> void:
	await _transition.fade_out()
	get_tree().paused = false
	var error: int = get_tree().change_scene_to_file(GAME_SCENE_PATH)
	if error != OK:
		push_error("GameManager: failed to load game scene (%d)" % error)
		await _transition.fade_in()
		return
	start_run()
	await _transition.fade_in()


func return_to_menu() -> void:
	await _transition.fade_out()
	get_tree().paused = false
	is_paused = false
	state = State.MENU
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var error: int = get_tree().change_scene_to_file(MENU_SCENE_PATH)
	if error != OK:
		push_error("GameManager: failed to load menu scene (%d)" % error)
	await _transition.fade_in()


func toggle_pause() -> void:
	set_paused(not is_paused)


func set_paused(paused: bool) -> void:
	if is_paused == paused:
		return
	is_paused = paused
	get_tree().paused = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
	EventBus.game_paused.emit(paused)


func get_run_time() -> float:
	if state == State.MENU:
		return 0.0
	return _now() - _run_start_time


# Private

func _on_player_died() -> void:
	if state == State.GAME_OVER:
		return
	state = State.GAME_OVER
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
