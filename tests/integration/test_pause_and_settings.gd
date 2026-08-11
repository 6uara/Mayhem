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
var _saved: Dictionary = {}


func before_each() -> void:
	# Settings are global and persist to disk; a test must not rewrite the player's.
	_saved = {}
	for key: String in SettingsManager.DEFAULTS:
		_saved[key] = SettingsManager.get_value(key)
	_menu = add_child_autofree(load(PAUSE_SCENE).instantiate())
	_settings = _menu.get_node("Settings")
	await wait_frames(2)


func after_each() -> void:
	for key: String in _saved:
		SettingsManager.set_value(key, _saved[key])
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
	assert_eq(built, SettingsScreen.SCHEMA.size() + host_row_nodes,
		"every schema entry should produce exactly one node (%d rows + headers), plus the host presenter row" % rows)


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
