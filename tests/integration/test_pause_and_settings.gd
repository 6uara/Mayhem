extends GutTest
## The pause menu and the options screen.
##
## Pausing worked long before anything drew it, which is exactly why this needs
## covering: the failure mode is not an error, it is a frozen frame with no way out.
##
## Nothing here actually freezes the tree. GameManager's pause sets
## `get_tree().paused`, and awaiting anything in that state would hang the runner -
## so pause is either driven through the signal, or asserted without yielding.

const PAUSE_SCENE: String = "res://scenes/ui/pause_menu.tscn"

var _menu: CanvasLayer
var _settings: SettingsScreen
const SettingsGuard = preload("res://tests/settings_guard.gd")

var _guard: SettingsGuard = SettingsGuard.new()


func before_each() -> void:
	# Settings are global and persist to disk; a test must not rewrite the player's.
	_guard.take()
	_menu = add_child_autofree(load(PAUSE_SCENE).instantiate())
	_settings = _menu.get_node("Settings")
	await wait_frames(2)


func after_each() -> void:
	_guard.restore()
	GameManager.is_paused = false
	get_tree().paused = false


# ------------------------------------------------------- the schema is honest

## Every row must point at a setting that actually exists.
##
## This is the failure the schema was chosen to prevent: a control that reads and
## writes a key nobody stores looks completely normal on screen, moves when dragged,
## and silently does nothing. Nothing else in the build would catch it.
func test_every_schema_key_is_a_real_setting() -> void:
	for entry: Dictionary in SettingsScreen.SCHEMA:
		if entry.has("section"):
			continue
		var key: String = String(entry["key"])
		assert_true(SettingsManager.DEFAULTS.has(key),
			"'%s' is on the options screen but not in SettingsManager.DEFAULTS" % key)


func test_every_schema_row_declares_a_label_and_type() -> void:
	for entry: Dictionary in SettingsScreen.SCHEMA:
		if entry.has("section"):
			continue
		assert_true(entry.has("label"), "row %s has no label" % entry)
		assert_true(entry.has("type"), "row %s has no type" % entry)


## The accessibility switches are the ones that matter most to reach, and they were
## the whole reason this screen exists - a view-bob toggle nobody can press is the
## same as no toggle at all.
func test_the_accessibility_switches_are_reachable() -> void:
	var keys: Array[String] = []
	for entry: Dictionary in SettingsScreen.SCHEMA:
		if not entry.has("section"):
			keys.push_back(String(entry["key"]))
	for required: String in ["accessibility/view_bob_enabled",
			"accessibility/screenshake_enabled", "input/mouse_sensitivity",
			"video/fov", "audio/master_volume"]:
		assert_true(keys.has(required), "%s has no control" % required)


func test_a_control_is_built_for_every_row() -> void:
	var rows: int = 0
	for entry: Dictionary in SettingsScreen.SCHEMA:
		if not entry.has("section"):
			rows += 1
	var built: int = _settings.get_node("Panel/Margin/Layout/Scroll/Rows").get_child_count()
	# Sections add their own headers, so built rows are the schema rows plus those.
	# _build_host_presenter_row() also appends a "HOST" section + its own row,
	# outside SCHEMA on purpose (the presenter list is data-driven - see its
	# docstring) - +2, as long as the presenter catalog isn't empty.
	var host_row_nodes: int = 2 if not NarratorManager.get_presenters().is_empty() else 0
	# Y la seccion CONTROLS: su header mas una fila por accion rebindeable.
	var control_rows: int = 1
	for entry: Array in SettingsManager.REBINDABLE_ACTIONS:
		if InputMap.has_action(entry[0]):
			control_rows += 1
	assert_eq(built, SettingsScreen.SCHEMA.size() + host_row_nodes + control_rows,
		"every schema entry should produce exactly one node (%d rows + headers), plus the host presenter and control rows" % rows)


# ---------------------------------------------------------------- rebinding

func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event


func test_every_rebindable_action_exists() -> void:
	for entry: Array in SettingsManager.REBINDABLE_ACTIONS:
		assert_true(InputMap.has_action(entry[0]), "%s is a real action" % entry[0])


func test_rebinding_replaces_the_key_and_keeps_a_gamepad_binding() -> void:
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	InputMap.action_add_event(&"jump", pad)
	SettingsManager.rebind_primary(&"jump", _key(KEY_V))
	var events: Array[InputEvent] = InputMap.action_get_events(&"jump")
	assert_eq(SettingsManager.describe_event(SettingsManager.get_primary_event(&"jump")),
		OS.get_keycode_string(KEY_V))
	assert_eq(events.size(), 2, "one key, and the pad button stays")
	assert_true(events.any(func(e: InputEvent) -> bool: return e is InputEventJoypadButton))


## Dos acciones en la misma tecla dejan a una inalcanzable: se cambian de lugar.
func test_taking_another_actions_key_swaps_them() -> void:
	var jump_before: InputEvent = SettingsManager.get_primary_event(&"jump")
	var dash_key: InputEvent = SettingsManager.get_primary_event(&"dash")
	SettingsManager.rebind_primary(&"jump", dash_key)
	assert_eq(SettingsManager.describe_event(SettingsManager.get_primary_event(&"jump")),
		SettingsManager.describe_event(dash_key))
	assert_eq(SettingsManager.describe_event(SettingsManager.get_primary_event(&"dash")),
		SettingsManager.describe_event(jump_before), "dash took jump's old key")


func test_the_options_screen_captures_the_next_key() -> void:
	await _open_options()
	_settings._start_capture(&"reload")
	var press := InputEventKey.new()
	press.physical_keycode = KEY_T
	press.pressed = true
	_settings._capture(press)
	assert_eq(SettingsManager.describe_event(SettingsManager.get_primary_event(&"reload")),
		OS.get_keycode_string(KEY_T))
	assert_eq((_settings._bind_buttons[&"reload"] as Button).text, OS.get_keycode_string(KEY_T))


func test_escape_cancels_a_capture_without_binding() -> void:
	await _open_options()
	var before: String = SettingsManager.describe_event(SettingsManager.get_primary_event(&"reload"))
	_settings._start_capture(&"reload")
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	_settings._capture(escape)
	assert_eq(SettingsManager.describe_event(SettingsManager.get_primary_event(&"reload")), before)
	assert_eq(_settings._capturing_action, &"", "and it stops listening")


# ------------------------------------------------------------------- video

func test_match_monitor_follows_the_refresh_rate() -> void:
	assert_eq(SettingsManager.resolve_fps_cap(SettingsManager.FPS_CAP_MONITOR, 143.9), 144)
	assert_eq(SettingsManager.resolve_fps_cap(SettingsManager.FPS_CAP_MONITOR, -1.0), 60,
		"a monitor that does not report falls back to 60, not uncapped")
	assert_eq(SettingsManager.resolve_fps_cap(0), 0, "uncapped stays uncapped")
	assert_eq(SettingsManager.resolve_fps_cap(120), 120)


func test_render_scale_below_native_turns_on_fsr() -> void:
	SettingsManager.set_value("video/render_scale", 67)
	SettingsManager.apply_all()
	var viewport: Viewport = get_tree().root
	assert_almost_eq(viewport.scaling_3d_scale, 0.67, 0.001)
	assert_eq(viewport.scaling_3d_mode, Viewport.SCALING_3D_MODE_FSR)
	SettingsManager.set_value("video/render_scale", 100)
	SettingsManager.apply_all()
	assert_eq(viewport.scaling_3d_mode, Viewport.SCALING_3D_MODE_BILINEAR, "native is not upscaled")


func test_anti_aliasing_options_reach_the_viewport() -> void:
	var viewport: Viewport = get_tree().root
	SettingsManager.set_value("video/anti_aliasing", SettingsManager.ANTI_ALIASING_MSAA_4X)
	SettingsManager.apply_all()
	assert_eq(viewport.msaa_3d, Viewport.MSAA_4X)
	SettingsManager.set_value("video/anti_aliasing", SettingsManager.ANTI_ALIASING_FXAA)
	SettingsManager.apply_all()
	assert_eq(viewport.msaa_3d, Viewport.MSAA_DISABLED)
	assert_eq(viewport.screen_space_aa, Viewport.SCREEN_SPACE_AA_FXAA)


# ------------------------------------------------------------------ behaviour

func test_the_menu_is_hidden_until_the_game_pauses() -> void:
	assert_false(_menu.get_node("Root").visible, "nothing is drawn while playing")


func test_pausing_shows_the_menu_and_unpausing_hides_it() -> void:
	EventBus.game_paused.emit(true)
	await wait_frames(2)
	assert_true(_menu.get_node("Root").visible, "a paused game has to show its menu")

	EventBus.game_paused.emit(false)
	await wait_frames(2)
	assert_false(_menu.get_node("Root").visible)


func test_game_manager_announces_pause() -> void:
	# No awaits while the tree is frozen: assert and release in the same frame.
	watch_signals(EventBus)
	GameManager.set_paused(true)
	var paused_state: bool = GameManager.is_paused
	GameManager.set_paused(false)

	assert_true(paused_state, "set_paused(true) has to take effect")
	assert_signal_emitted(EventBus, "game_paused")
	assert_false(get_tree().paused, "the test must leave the tree running")


func test_opening_options_replaces_the_pause_panel() -> void:
	EventBus.game_paused.emit(true)
	await wait_frames(2)
	_menu.get_node("Root/Panel/Margin/Layout/OptionsButton").pressed.emit()
	await wait_frames(2)

	assert_true(_settings.visible, "options open")
	assert_false(_menu.get_node("Root").visible,
		"the two panels must not stack on top of each other")


func test_closing_options_returns_to_the_pause_panel() -> void:
	GameManager.is_paused = true  # still paused underneath, tree left running
	EventBus.game_paused.emit(true)
	await wait_frames(2)
	_menu.get_node("Root/Panel/Margin/Layout/OptionsButton").pressed.emit()
	await wait_frames(2)
	_settings.close()
	await wait_frames(2)

	assert_false(_settings.visible)
	assert_true(_menu.get_node("Root").visible, "back lands on the pause menu")


## Unpausing straight out of the options screen must not leave it armed to reappear
## on top of the next pause.
func test_unpausing_from_options_closes_everything() -> void:
	EventBus.game_paused.emit(true)
	await wait_frames(2)
	_menu.get_node("Root/Panel/Margin/Layout/OptionsButton").pressed.emit()
	await wait_frames(2)

	EventBus.game_paused.emit(false)
	await wait_frames(2)
	assert_false(_settings.visible, "options close with the pause that opened them")
	assert_false(_menu.get_node("Root").visible)


func test_settings_reach_the_manager() -> void:
	_settings.open()
	await wait_frames(2)
	SettingsManager.set_value("audio/sfx_volume", 0.33)
	_settings._refresh_all()
	assert_almost_eq(float(SettingsManager.get_value("audio/sfx_volume")), 0.33, 0.001)


func test_reset_hints_button_clears_seen_tutorial_hints() -> void:
	SaveManager.mark_hint_seen(&"dash")
	_settings.open()
	await wait_frames(2)

	_settings._reset_hints_button.pressed.emit()
	assert_false(SaveManager.has_seen_hint(&"dash"),
		"the reset button must forget every hint the player has already seen")
	SaveManager.clear_tutorial_hints()


# ------------------------------------------------- apply changes

## El pedido del playtest: que haya un boton que confirme, y que solo se habilite
## cuando hay algo que confirmar.

func _open_options() -> SettingsScreen:
	_settings.open()
	await wait_physics_frames(2)
	return _settings


func test_apply_starts_disabled_with_nothing_to_apply() -> void:
	await _open_options()
	assert_true(_settings._apply_button.disabled, "recien abierto no hay nada que aplicar")


func test_changing_a_setting_enables_apply() -> void:
	await _open_options()
	_settings._commit("video/fov", 111.0)
	await wait_physics_frames(2)
	assert_false(_settings._apply_button.disabled, "un cambio habilita el boton")


func test_applying_saves_and_disables_the_button_again() -> void:
	await _open_options()
	_settings._commit("video/fov", 112.0)
	_settings._on_apply_pressed()
	await wait_physics_frames(2)

	assert_eq(SettingsManager.get_value("video/fov"), 112.0, "el valor quedo")
	assert_true(_settings._is_dirty() == false, "ya no hay nada pendiente")


## Back descarta: es lo que le da sentido al boton.
func test_back_discards_what_was_never_applied() -> void:
	await _open_options()
	var before: float = float(SettingsManager.get_value("video/fov"))
	_settings._commit("video/fov", 119.0)
	_settings.close()
	await wait_physics_frames(2)

	assert_eq(float(SettingsManager.get_value("video/fov")), before,
		"salir sin aplicar deja todo como estaba")


func test_back_keeps_what_was_applied() -> void:
	await _open_options()
	_settings._commit("video/fov", 118.0)
	_settings._on_apply_pressed()
	_settings.close()
	await wait_physics_frames(2)

	assert_eq(float(SettingsManager.get_value("video/fov")), 118.0,
		"lo aplicado sobrevive a Back")
