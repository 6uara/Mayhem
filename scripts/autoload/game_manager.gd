extends Node
## Match state machine and run lifecycle. Knows nothing about UI layout.

enum State { MENU, PLAYING, SHOPPING, GAME_OVER }

const GAME_SCENE_PATH: String = "res://scenes/main/game.tscn"
const MENU_SCENE_PATH: String = "res://scenes/main/main_menu.tscn"
const TRANSITION_SCENE: PackedScene = preload("res://scenes/ui/scene_transition.tscn")
const LOADING_SCENE: PackedScene = preload("res://scenes/ui/loading_screen.tscn")

## How long a load may take before the player is shown a loading screen.
##
## Almost every scene change in a session is warm: the game scene is already in
## the resource cache, the load returns in a frame or two, and putting a progress
## bar up for that long would be a flash of furniture rather than information -
## and it would cost two extra fades out of restart_run's two-second budget.
##
## A cold load is the other case entirely. Measured at over ten seconds the first
## time the game scene is read off disk, and that is what this is for.
const LOADING_SCREEN_GRACE: float = 0.35
## Ceiling on one scene load. A threaded load that never reports finished must not
## strand the player on a progress bar forever - same reasoning as
## SceneTransition.safety_timeout, and the same shape of answer.
const LOAD_TIMEOUT: float = 60.0

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
## Also GameManager's own child, and for the same reason: it has to outlive the
## scene it is covering for.
var _loading: LoadingScreen


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.player_died.connect(_on_player_died)
	_transition = TRANSITION_SCENE.instantiate()
	add_child(_transition)
	_loading = LOADING_SCENE.instantiate()
	add_child(_loading)


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
	var scene: PackedScene = await _prepare_scene(GAME_SCENE_PATH)
	get_tree().paused = false
	if scene == null:
		await _reveal()
		return
	var error: int = get_tree().change_scene_to_packed(scene)
	if error != OK:
		push_error("GameManager: failed to enter game scene (%d)" % error)
		await _reveal()
		return
	start_run()
	await _reveal()


func return_to_menu() -> void:
	var scene: PackedScene = await _prepare_scene(MENU_SCENE_PATH)
	get_tree().paused = false
	is_paused = false
	state = State.MENU
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if scene != null and get_tree().change_scene_to_packed(scene) != OK:
		push_error("GameManager: failed to enter menu scene")
	await _reveal()


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

## Covers the screen and loads `path` off the main thread, returning the scene
## ready to be swapped in - or null if it could not be loaded.
##
## The threaded load is the whole point. change_scene_to_file() reads the scene
## synchronously, so the process stops answering for as long as that takes; cold,
## the game scene measured over ten seconds of a frozen window behind a fade that
## had already finished playing.
##
## The loading screen is not put up immediately. Warm - which is every scene
## change after the first - this returns in a frame or two, and a progress bar
## that appears and vanishes inside 300ms is worse than none: it also costs the
## two extra fades needed to show and hide it, out of restart_run's two-second
## budget. Past LOADING_SCREEN_GRACE the load is slow enough to be worth
## explaining, and by then those fades cost nothing next to the wait.
func _prepare_scene(path: String) -> PackedScene:
	await _transition.fade_out()

	var error: int = ResourceLoader.load_threaded_request(path, "PackedScene")
	if error != OK:
		push_error("GameManager: could not start loading %s (%d)" % [path, error])
		return null

	var elapsed: float = 0.0
	var progress: Array = []
	while true:
		var status: int = ResourceLoader.load_threaded_get_status(path, progress)
		if status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if status != ResourceLoader.THREAD_LOAD_LOADED:
				push_error("GameManager: loading %s failed (status %d)" % [path, status])
				_hide_loading()
				return null
			break

		if elapsed >= LOAD_TIMEOUT:
			push_error("GameManager: loading %s timed out after %.0fs" % [path, LOAD_TIMEOUT])
			_hide_loading()
			return null

		if _loading != null:
			if not _loading.visible and elapsed >= LOADING_SCREEN_GRACE:
				_loading.begin()
				# Revealed rather than snapped in: the screen is currently under
				# the transition's cover, and uncovering anything is a fade.
				await _transition.fade_in()
			if not progress.is_empty():
				_loading.set_progress(float(progress[0]))

		await get_tree().process_frame
		elapsed += get_process_delta_time()

	# Only meaningful if the screen was ever shown; harmless otherwise.
	if _loading != null and _loading.visible:
		_loading.set_progress(1.0)
		await _transition.fade_out()

	var scene := ResourceLoader.load_threaded_get(path) as PackedScene
	if scene == null:
		push_error("GameManager: %s is not a PackedScene" % path)
	return scene


## Takes the cover - and the loading screen under it - back off.
func _reveal() -> void:
	_hide_loading()
	await _transition.fade_in()


func _hide_loading() -> void:
	if _loading != null:
		_loading.finish()


func _on_player_died() -> void:
	if state == State.GAME_OVER:
		return
	state = State.GAME_OVER
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
