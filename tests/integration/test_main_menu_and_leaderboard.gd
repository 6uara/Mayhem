extends GutTest
## The front page and the run history.
##
## The menu was a placeholder that outlived its job by several phases, and the
## leaderboard had been written to disk since Phase 4 and read back by nothing -
## the reason to chase a par time existed and was invisible. Neither failure
## announces itself, so both get pinned here.

const MENU_SCENE: String = "res://scenes/main/main_menu.tscn"

var _menu: Control
var _saved: Array[Dictionary] = []


func before_each() -> void:
	# The leaderboard is real user data on disk; a test must not overwrite it.
	_saved = SaveManager.get_entries()
	_menu = add_child_autofree(load(MENU_SCENE).instantiate())
	await wait_frames(2)


func after_each() -> void:
	SaveManager.clear_leaderboard()
	for entry: Dictionary in _saved:
		SaveManager.submit_score(int(entry.get("score", 0)),
			float(entry.get("time", 0.0)), int(entry.get("waves", 0)))


func _panel(name: String) -> Control:
	return _menu.get_node(name)


# ------------------------------------------------------------------ the menu

func test_the_menu_uses_the_game_theme() -> void:
	assert_not_null(_menu.theme,
		"the first screen of the game cannot be the one that skips the theme")


func test_every_menu_action_is_reachable() -> void:
	var layout: Control = _panel("Root/Panel/Margin/Layout")
	for button: String in ["PlayButton", "LeaderboardButton", "OptionsButton", "QuitButton"]:
		assert_not_null(layout.get_node_or_null(button), button)


## Opening a panel replaces the menu rather than stacking on top of it.
func test_opening_a_panel_hides_the_menu_and_closing_restores_it() -> void:
	var root: Control = _panel("Root")
	var leaderboard: LeaderboardPanel = _panel("Leaderboard")

	_panel("Root/Panel/Margin/Layout/LeaderboardButton").pressed.emit()
	await wait_frames(2)
	assert_true(leaderboard.visible, "the board opens")
	assert_false(root.visible, "and the menu gets out of its way")

	leaderboard.close()
	await wait_frames(2)
	assert_false(leaderboard.visible)
	assert_true(root.visible, "back lands on the menu")


## The same settings scene the pause menu uses - one screen, so it cannot behave
## differently depending on where it was opened from.
func test_options_opens_the_shared_settings_screen() -> void:
	var settings: SettingsScreen = _panel("Settings")
	_panel("Root/Panel/Margin/Layout/OptionsButton").pressed.emit()
	await wait_frames(2)
	assert_true(settings.visible)
	settings.close()


# ----------------------------------------------------------- the leaderboard

func test_an_empty_board_says_so_rather_than_showing_nothing() -> void:
	SaveManager.clear_leaderboard()
	var leaderboard: LeaderboardPanel = _panel("Leaderboard")
	leaderboard.open()
	await wait_frames(2)

	assert_true(_panel("Leaderboard/Panel/Margin/Layout/EmptyState").visible,
		"a first run should be told the board is empty, not shown a blank grid")


func test_submitted_runs_appear_on_the_board() -> void:
	SaveManager.clear_leaderboard()
	SaveManager.submit_score(1200, 240.0, 7)
	SaveManager.submit_score(3400, 300.0, 10)

	var leaderboard: LeaderboardPanel = _panel("Leaderboard")
	leaderboard.open()
	await wait_frames(2)

	var rows: VBoxContainer = _panel("Leaderboard/Panel/Margin/Layout/Scroll/Rows")
	assert_false(_panel("Leaderboard/Panel/Margin/Layout/EmptyState").visible)
	# Two runs plus the header row.
	assert_eq(rows.get_child_count(), 3, "both runs are listed under a header")


func test_the_menu_shows_the_best_score() -> void:
	SaveManager.clear_leaderboard()
	SaveManager.submit_score(4321, 200.0, 9)

	var fresh: Control = add_child_autofree(load(MENU_SCENE).instantiate())
	await wait_frames(2)
	var best: Label = fresh.get_node("Root/Panel/Margin/Layout/BestRow/Value")
	assert_eq(best.text, "4321", "the number the next run is for belongs on the front page")
