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
	step.text = "%s with {crouch_slide}" % title
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
	for goal: StringName in [&"move", &"jump", &"slide", &"fast_fall", &"grapple", &"fire", &"reload"]:
		assert_true(goals.has(goal), "enseña %s" % goal)
	assert_lt(info_time, 30.0, "lo que se lee sin hacer nada tiene que ser poco")


func test_an_action_step_waits_for_the_action() -> void:
	var director: TutorialDirector = _director([_step(&"fast_fall", "DIVE"), _step(&"", "INFO")])
	director.begin()
	assert_true(director.is_running)
	director._process(5.0)
	assert_eq(director.get_step_index(), 0, "no pasa solo")
	EventBus.fast_fall_landed.emit()
	director._process(TutorialDirector.STEP_GAP + 0.01)
	assert_eq(director.get_step_index(), 1)
	assert_true(SaveManager.has_seen_hint(&"fast_fall"), "el hint de primera vez queda aprendido")


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
	var director: TutorialDirector = _director([step, _step(&"fast_fall", "DIVE")])
	director.begin()
	assert_eq(director.current_step().goal, &"fast_fall")


func test_skipping_ends_it_and_remembers() -> void:
	var director: TutorialDirector = _director([_step(&"fast_fall", "DIVE")])
	watch_signals(director)
	director.begin()
	TutorialHintManager.skip_tutorial()
	assert_false(director.is_running)
	assert_signal_emitted_with_parameters(director, "finished", [true])
	assert_false(director.should_run(), "no vuelve en la run siguiente")


func test_the_skip_key_skips() -> void:
	var director: TutorialDirector = _director([_step(&"fast_fall", "DIVE")])
	director.begin()
	var press := InputEventAction.new()
	press.action = &"skip_tutorial"
	press.pressed = true
	director._unhandled_input(press)
	assert_false(director.is_running)


func test_a_completed_tutorial_does_not_run_again() -> void:
	SaveManager.mark_hint_seen(TutorialDirector.COMPLETED_ID)
	var director: TutorialDirector = _director([_step(&"fast_fall", "DIVE")])
	watch_signals(director)
	director.begin()
	assert_false(director.is_running)
	assert_signal_emitted(director, "finished", "quien espera no se queda esperando")


func test_the_text_names_the_bound_key() -> void:
	var text: String = TutorialDirector.resolve_text("Dive with {crouch_slide}. Move with {move}.")
	assert_false(text.contains("{"), text)
	assert_true(text.contains(TutorialHintManager.key_label(&"crouch_slide")))


func test_first_time_hints_stay_quiet_during_the_tutorial() -> void:
	var director: TutorialDirector = _director([_step(&"fast_fall", "DIVE")])
	director.begin()
	TutorialHintManager._queue.clear()
	TutorialHintManager._fire(&"reload")
	assert_eq(TutorialHintManager._queue.size(), 0)
	director.skip()


## La partida no empieza hasta que el tutorial termina.
func test_the_first_wave_waits_for_the_tutorial() -> void:
	var director: TutorialDirector = _director([_step(&"fast_fall", "DIVE")])
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
	var director: TutorialDirector = _director([_step(&"fast_fall", "DIVE")])
	director.begin()
	EventBus.game_paused.emit(true)
	assert_true(button.visible)
	button.pressed.emit()
	assert_false(director.is_running)
	EventBus.game_paused.emit(false)


func _player_in_scene() -> Player:
	var player: Player = load("res://scenes/player/player.tscn").instantiate()
	add_child_autofree(player)
	return player


func _pad_button(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	return event


func _back_to_keyboard() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	TutorialHintManager._input(key)


func test_every_shipped_text_resolves_clean_in_both_forms() -> void:
	var catalog: TutorialStepCatalog = load(TutorialDirector.STEPS_PATH)
	for step: TutorialStep in catalog.steps:
		for text: String in [step.text, step.nudge]:
			var plain: String = TutorialDirector.resolve_text(text)
			assert_false(plain.contains("{") or plain.contains("["), plain)
			var rich: String = TutorialDirector.resolve_rich_text(text)
			assert_false(rich.contains("{"), rich)
			for tag: String in ["player", "grapple", "hazard", "reward", "spawn"]:
				assert_false(rich.contains("[%s]" % tag), rich)
		if step.setup_action != &"":
			assert_true(InputMap.has_action(step.setup_action), String(step.setup_action))


func test_the_rich_text_highlights_the_key_and_paints_the_colours() -> void:
	var rich: String = TutorialDirector.resolve_rich_text("Press {jump} on [grapple]violet[/grapple].")
	var key: String = "[color=#%s]%s[/color]" % [Tokens.PLAYER.to_html(false),
		TutorialHintManager.key_label(&"jump")]
	assert_true(rich.contains(key), rich)
	assert_true(rich.contains("[color=#%s]violet[/color]" % Tokens.WORLD_GRAPPLE.to_html(false)), rich)


func test_the_keys_a_text_names_come_in_order_without_repeats() -> void:
	var actions: Array[StringName] = TutorialDirector.actions_in("{fire}, {ads} and {fire}. {nope}")
	assert_eq(actions, [&"fire", &"ads"] as Array[StringName])


## Una tecla que late tiene que servir: la picada no late en el piso.
func test_the_dive_key_only_lights_up_in_the_air() -> void:
	var step: TutorialStep = _step(&"fast_fall", "DIVE")
	step.ready_when = &"airborne"
	step.setup_action = &"jump"
	var player: Player = _player_in_scene()
	var director: TutorialDirector = _director([step])
	director.begin()
	director._player = player
	player.movement.state = MovementComponent.State.GROUNDED
	director._process(0.01)
	assert_false(director._key_ready, "en el piso la pedida es saltar")
	watch_signals(TutorialHintManager)
	player.movement.state = MovementComponent.State.AIRBORNE
	director._process(0.01)
	assert_signal_emitted_with_parameters(TutorialHintManager, "tutorial_key_ready_changed", [true])
	director.skip()


func test_the_grapple_key_waits_for_an_anchor_in_range() -> void:
	var step: TutorialStep = _step(&"grapple", "GRAPPLE")
	step.ready_when = &"anchor_in_range"
	var player: Player = _player_in_scene()
	var director: TutorialDirector = _director([step])
	director.begin()
	director._player = player
	player.grapple.is_anchor_in_range = false
	assert_false(director._is_key_ready(step))
	player.grapple.is_anchor_in_range = true
	assert_true(director._is_key_ready(step))
	director.skip()


func test_a_stuck_player_gets_the_nudge_once_and_a_rebind_keeps_it() -> void:
	var step: TutorialStep = _step(&"fast_fall", "DIVE")
	step.nudge = "In the air, {jump} first"
	step.nudge_after = 2.0
	var director: TutorialDirector = _director([step])
	director.begin()
	watch_signals(TutorialHintManager)
	director._process(1.0)
	assert_signal_emit_count(TutorialHintManager, "tutorial_nudged", 0)
	director._process(1.1)
	director._process(0.1)
	assert_signal_emit_count(TutorialHintManager, "tutorial_nudged", 1)
	EventBus.settings_applied.emit()
	var shown: Array = get_signal_parameters(TutorialHintManager, "tutorial_step_shown")
	assert_true(String(shown[1]).contains("In the air"), "el texto reescrito sigue siendo la ayuda")
	director.skip()


func test_the_waypoint_marks_the_nearest_and_leaves_with_the_step() -> void:
	var far := Node3D.new()
	var near := Node3D.new()
	add_child_autofree(far)
	add_child_autofree(near)
	far.position = Vector3(100.0, 0.0, 0.0)
	near.position = Vector3(5.0, 0.0, 0.0)
	far.add_to_group(&"tutorial_test_mark")
	near.add_to_group(&"tutorial_test_mark")
	var player: Player = _player_in_scene()
	player.global_position = Vector3.ZERO
	var step: TutorialStep = _step(&"grapple", "GRAPPLE")
	step.waypoint_group = &"tutorial_test_mark"
	var director: TutorialDirector = _director([step])
	director._player = player
	assert_eq(director._waypoint_for(step), near)
	director.begin()
	watch_signals(TutorialHintManager)
	EventBus.grapple_started.emit(Vector3.ZERO)
	assert_signal_emitted_with_parameters(TutorialHintManager, "tutorial_waypoint_changed", [null])
	director.skip()


func test_grabbing_a_gamepad_rewrites_the_step_with_its_buttons() -> void:
	var director: TutorialDirector = _director([_step(&"fast_fall", "DIVE")])
	director.begin()
	watch_signals(TutorialHintManager)
	TutorialHintManager._input(_pad_button(JOY_BUTTON_A))
	assert_true(TutorialHintManager.uses_gamepad())
	assert_signal_emitted(TutorialHintManager, "tutorial_step_shown")
	assert_eq(TutorialHintManager.key_label(&"crouch_slide"), "B")
	assert_eq(TutorialHintManager.key_label(&"fire"), "RT")
	assert_eq(TutorialDirector.resolve_text("{move}"), "Left Stick", "un stick, no cuatro")
	_back_to_keyboard()
	assert_false(TutorialHintManager.uses_gamepad())
	director.skip()


func test_a_drifting_stick_does_not_take_the_screen_from_the_keyboard() -> void:
	var drift := InputEventJoypadMotion.new()
	drift.axis = JOY_AXIS_LEFT_X
	drift.axis_value = 0.2
	TutorialHintManager._input(drift)
	assert_false(TutorialHintManager.uses_gamepad())
	drift.axis_value = 0.9
	TutorialHintManager._input(drift)
	assert_true(TutorialHintManager.uses_gamepad())
	_back_to_keyboard()


func test_the_key_row_asks_for_the_setup_first_then_for_the_key() -> void:
	var keys := TutorialKeys.new()
	add_child_autofree(keys)
	keys.show_actions([&"crouch_slide"] as Array[StringName], &"jump", false)
	assert_true(keys.get_setup_cap().is_asked, "primero saltar")
	assert_false(keys.get_main_caps()[0].is_asked)
	keys.set_key_ready(true)
	assert_false(keys.get_setup_cap().is_asked)
	assert_true(keys.get_main_caps()[0].is_asked, "ahora si, la picada")


func test_only_the_first_named_key_is_asked() -> void:
	var keys := TutorialKeys.new()
	add_child_autofree(keys)
	keys.show_actions([&"fire", &"ads"] as Array[StringName])
	assert_eq(keys.get_caps().size(), 2)
	assert_true(keys.get_caps()[0].is_asked)
	assert_false(keys.get_caps()[1].is_asked, "apuntar se nombra, no se pide")


func test_move_draws_the_four_keys_on_a_keyboard_and_one_stick_on_a_pad() -> void:
	var keys := TutorialKeys.new()
	add_child_autofree(keys)
	keys.show_actions([&"move"] as Array[StringName])
	assert_eq(keys.get_main_caps().size(), 4)
	TutorialHintManager._input(_pad_button(JOY_BUTTON_A))
	keys.show_actions([&"move"] as Array[StringName])
	assert_eq(keys.get_main_caps().size(), 1)
	assert_eq(keys.get_main_caps()[0].get_label(), "LEFT STICK")
	_back_to_keyboard()


func test_a_key_cap_answers_the_press_and_stays_lit_when_done() -> void:
	var cap: KeyCap = KeyCap.new().setup(&"jump")
	add_child_autofree(cap)
	var press := InputEventAction.new()
	press.action = &"jump"
	press.pressed = true
	cap._input(press)
	assert_true(cap.is_lit())
	press.pressed = false
	cap._input(press)
	assert_false(cap.is_lit())
	cap.mark_done()
	assert_true(cap.is_lit())


func test_a_mouse_binding_draws_a_mouse_and_a_rebind_to_a_key_draws_the_key() -> void:
	var fire_events: Array[InputEvent] = InputMap.action_get_events(&"fire")
	var mouse_cap: KeyCap = KeyCap.new().setup(&"fire")
	autofree(mouse_cap)
	assert_true(mouse_cap.is_mouse_glyph())
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	InputMap.action_erase_events(&"fire")
	InputMap.action_add_event(&"fire", key)
	var cap: KeyCap = KeyCap.new().setup(&"fire")
	autofree(cap)
	InputMap.action_erase_events(&"fire")
	for event: InputEvent in fire_events:
		InputMap.action_add_event(&"fire", event)
	assert_false(cap.is_mouse_glyph())
	assert_eq(cap.get_label(), "F")


func test_the_waypoint_stays_put_on_screen_and_sticks_to_the_edge_off_it() -> void:
	var area := Vector2(1920.0, 1080.0)
	var on: Dictionary = TutorialWaypoint.place(Vector2(1000.0, 500.0), false, area, 96.0)
	assert_true(on[&"on_screen"])
	assert_eq(on[&"point"], Vector2(1000.0, 500.0))
	var right: Dictionary = TutorialWaypoint.place(Vector2(5000.0, 540.0), false, area, 96.0)
	assert_false(right[&"on_screen"])
	assert_almost_eq(right[&"point"].x, 1920.0 - 96.0, 0.01)
	assert_gt(right[&"direction"].x, 0.9)


## Detras de la camara la proyeccion sale espejada: apuntar donde "cae" mandaria al
## jugador para el otro lado.
func test_the_waypoint_points_the_right_way_when_the_target_is_behind() -> void:
	var area := Vector2(1920.0, 1080.0)
	var behind: Dictionary = TutorialWaypoint.place(Vector2(1200.0, 540.0), true, area, 96.0)
	assert_false(behind[&"on_screen"])
	assert_lt(behind[&"direction"].x, 0.0)
