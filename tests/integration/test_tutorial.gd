extends GutTest
## El tutorial de arranque: corto, la partida lo espera, y se saltea con una
## tecla o desde la pausa.

const PAUSE_SCENE: String = "res://scenes/ui/pause_menu.tscn"

## El archivo de hints del jugador, tal cual, para devolverlo al terminar.
var _saved_hints: Variant = null


func before_each() -> void:
	_saved_hints = null
	if FileAccess.file_exists(SaveManager.TUTORIAL_SAVE_PATH):
		_saved_hints = FileAccess.get_file_as_string(SaveManager.TUTORIAL_SAVE_PATH)
	SaveManager.clear_tutorial_hints()


func after_each() -> void:
	if _saved_hints == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.TUTORIAL_SAVE_PATH))
	else:
		var file: FileAccess = FileAccess.open(SaveManager.TUTORIAL_SAVE_PATH, FileAccess.WRITE)
		file.store_string(String(_saved_hints))
		file.close()
	SaveManager.load_tutorial_hints()
	WaveManager.reset()
	WaveManager.setup([])


func _step(goal: StringName, title: String, duration: float = 1.0) -> TutorialStep:
	var step := TutorialStep.new()
	step.goal = goal
	step.title = title
	step.text = "%s with {dash}" % title
	step.duration = duration
	step.max_time = 30.0
	step.teaches_hint = goal
	return step


func _director(steps: Array[TutorialStep]) -> TutorialDirector:
	var catalog := TutorialStepCatalog.new()
	catalog.steps = steps
	var director := TutorialDirector.new()
	director.catalog = catalog
	add_child_autofree(director)
	return director


func test_the_shipped_tutorial_is_short_and_covers_the_basics() -> void:
	var catalog: TutorialStepCatalog = load(TutorialDirector.STEPS_PATH)
	var goals: Array[StringName] = []
	var info_time: float = 0.0
	for step: TutorialStep in catalog.steps:
		goals.append(step.goal)
		if step.goal == &"":
			info_time += step.duration
	for goal: StringName in [&"move", &"jump", &"slide", &"dash", &"grapple", &"fire", &"reload"]:
		assert_true(goals.has(goal), "enseña %s" % goal)
	assert_lt(info_time, 30.0, "lo que se lee sin hacer nada tiene que ser poco")


func test_an_action_step_waits_for_the_action() -> void:
	var director: TutorialDirector = _director([_step(&"dash", "DASH"), _step(&"", "INFO")])
	director.begin()
	assert_true(director.is_running)
	director._process(5.0)
	assert_eq(director.get_step_index(), 0, "no pasa solo")
	EventBus.dash_used.emit(2)
	director._process(TutorialDirector.STEP_GAP + 0.01)
	assert_eq(director.get_step_index(), 1)
	assert_true(SaveManager.has_seen_hint(&"dash"), "el hint de primera vez queda aprendido")


func test_an_info_step_passes_on_its_own() -> void:
	var director: TutorialDirector = _director([_step(&"", "INFO", 2.0)])
	watch_signals(director)
	director.begin()
	director._process(2.1)
	assert_signal_emitted_with_parameters(director, "finished", [false])
	assert_true(TutorialDirector.is_completed())


func test_no_step_can_trap_the_player() -> void:
	var step: TutorialStep = _step(&"grapple", "GRAPPLE")
	step.max_time = 3.0
	var director: TutorialDirector = _director([step])
	watch_signals(director)
	director.begin()
	director._process(3.1)
	assert_signal_emitted(director, "finished")


func test_a_step_the_arena_cannot_teach_is_skipped() -> void:
	var step: TutorialStep = _step(&"grapple", "GRAPPLE")
	step.requires_group = &"no_such_thing_in_this_test"
	var director: TutorialDirector = _director([step, _step(&"dash", "DASH")])
	director.begin()
	assert_eq(director.current_step().goal, &"dash")


func test_skipping_ends_it_and_remembers() -> void:
	var director: TutorialDirector = _director([_step(&"dash", "DASH")])
	watch_signals(director)
	director.begin()
	TutorialHintManager.skip_tutorial()
	assert_false(director.is_running)
	assert_signal_emitted_with_parameters(director, "finished", [true])
	assert_false(director.should_run(), "no vuelve en la run siguiente")


func test_the_skip_key_skips() -> void:
	var director: TutorialDirector = _director([_step(&"dash", "DASH")])
	director.begin()
	var press := InputEventAction.new()
	press.action = &"skip_tutorial"
	press.pressed = true
	director._unhandled_input(press)
	assert_false(director.is_running)


func test_a_completed_tutorial_does_not_run_again() -> void:
	SaveManager.mark_hint_seen(TutorialDirector.COMPLETED_ID)
	var director: TutorialDirector = _director([_step(&"dash", "DASH")])
	watch_signals(director)
	director.begin()
	assert_false(director.is_running)
	assert_signal_emitted(director, "finished", "quien espera no se queda esperando")


func test_the_text_names_the_bound_key() -> void:
	var text: String = TutorialDirector.resolve_text("Dash with {dash}. Move with {move}.")
	assert_false(text.contains("{"), text)
	assert_true(text.contains(TutorialHintManager.key_label(&"dash")))


func test_first_time_hints_stay_quiet_during_the_tutorial() -> void:
	var director: TutorialDirector = _director([_step(&"dash", "DASH")])
	director.begin()
	TutorialHintManager._queue.clear()
	TutorialHintManager._fire(&"reload")
	assert_eq(TutorialHintManager._queue.size(), 0)
	director.skip()


## La partida no empieza hasta que el tutorial termina.
func test_the_first_wave_waits_for_the_tutorial() -> void:
	var director: TutorialDirector = _director([_step(&"dash", "DASH")])
	var wave := WaveData.new()
	var group := SpawnGroup.new()
	group.enemy_data = EnemyData.new()
	group.count = 1
	group.spawn_door_ids = [&"door_01"] as Array[StringName]
	wave.spawn_groups = [group]
	var match_director := MatchDirector.new()
	match_director.waves = [wave]
	match_director.first_wave_delay = 0.0
	match_director.tutorial = director
	add_child_autofree(match_director)
	await wait_physics_frames(3)
	assert_true(director.is_running)
	assert_eq(WaveManager.current_index, -1, "la oleada uno espera")
	director.skip()
	await wait_physics_frames(3)
	assert_eq(WaveManager.current_index, 0, "y arranca apenas termina")


func test_the_pause_menu_offers_the_skip_only_during_the_tutorial() -> void:
	var pause: CanvasLayer = add_child_autofree((load(PAUSE_SCENE) as PackedScene).instantiate())
	await wait_frames(1)
	var button: Button = pause.get_node("Root/Panel/Margin/Layout/SkipTutorialButton")
	EventBus.game_paused.emit(true)
	assert_false(button.visible)
	var director: TutorialDirector = _director([_step(&"dash", "DASH")])
	director.begin()
	EventBus.game_paused.emit(true)
	assert_true(button.visible)
	button.pressed.emit()
	assert_false(director.is_running)
	EventBus.game_paused.emit(false)
