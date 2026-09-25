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
var _saved_profiles: Array[String] = []


func before_each() -> void:
	# The leaderboard is real user data on disk; a test must not overwrite it.
	# Los perfiles tambien: guardar un puntaje recuerda el nombre, asi que correr
	# la suite no puede dejarle "TESTER" en la lista a quien juega en esta maquina.
	_saved = SaveManager.get_entries()
	_saved_profiles = SaveManager.get_profiles()
	_menu = add_child_autofree(load(MENU_SCENE).instantiate())
	await wait_frames(2)


func after_each() -> void:
	SaveManager.clear_leaderboard()
	for entry: Dictionary in _saved:
		SaveManager.submit_score(int(entry.get("score", 0)),
			float(entry.get("time", 0.0)), int(entry.get("waves", 0)),
			String(entry.get("name", SaveManager.DEFAULT_NAME)))
	SaveManager.forget_profiles()
	for index: int in range(_saved_profiles.size() - 1, -1, -1):
		SaveManager.remember_profile(_saved_profiles[index])


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


# ------------------------------------------------------------- los nombres

## Lo que la tabla no tenia: quien hizo el puntaje.
func test_a_run_carries_the_name_it_was_saved_under() -> void:
	SaveManager.clear_leaderboard()
	SaveManager.submit_score(500, 100.0, 3, "Nyx")

	var entries: Array[Dictionary] = SaveManager.get_entries()
	assert_eq(entries.size(), 1)
	assert_eq(String(entries[0].get("name", "")), "NYX",
		"los nombres se guardan normalizados, para que la columna no baile")


## Las runs guardadas antes de que existieran los nombres siguen siendo runs.
func test_a_legacy_entry_without_a_name_still_loads() -> void:
	SaveManager.clear_leaderboard()
	var file: FileAccess = FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify([
		{"score": 999, "time": 120.0, "waves": 4, "date": "2026-01-01"}]))
	file.close()
	SaveManager.load_leaderboard()

	var entries: Array[Dictionary] = SaveManager.get_entries()
	assert_eq(entries.size(), 1, "no se pierde por no tener nombre")
	assert_eq(String(entries[0].get("name", "")), SaveManager.DEFAULT_NAME)


# ------------------------------------------------------------- los trofeos

## Los trofeos viajan con la fila: en un juego sin meta-progresion no hay donde
## mas ponerlos, y ahi es donde significan algo.
func test_a_run_keeps_the_trophies_it_was_saved_with() -> void:
	SaveManager.clear_leaderboard()
	SaveManager.submit_score(2000, 300.0, 10, "Nyx",
		[RunRecord.CHAMPION, RunRecord.FLAWLESS])

	var entries: Array[Dictionary] = SaveManager.get_entries()
	var trophies: Array = entries[0].get("trophies", [])
	assert_eq(trophies.size(), 2)
	assert_true(trophies.has(String(RunRecord.CHAMPION)),
		"guardados como String, que es lo que vuelve del JSON")


## Una run sin trofeos y una guardada antes de que existieran se leen igual, que
## es lo correcto: ninguna de las dos gano ninguno.
func test_a_legacy_entry_without_trophies_still_loads() -> void:
	SaveManager.clear_leaderboard()
	var legacy: FileAccess = FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
	legacy.store_string(JSON.stringify([
		{"name": "OLD", "score": 999, "time": 120.0, "waves": 4, "date": "2026-01-01"}]))
	legacy.close()
	SaveManager.load_leaderboard()

	var entries: Array[Dictionary] = SaveManager.get_entries()
	assert_eq(entries.size(), 1)
	assert_eq((entries[0].get("trophies", null) as Array).size(), 0)


## Diez y no veinte: entrar a la tabla tiene que volver a ser un logro.
func test_the_board_keeps_only_the_best_ten() -> void:
	SaveManager.clear_leaderboard()
	for i: int in SaveManager.MAX_ENTRIES + 5:
		SaveManager.submit_score(100 + i * 10, 200.0, 5, "Nyx")

	var entries: Array[Dictionary] = SaveManager.get_entries()
	assert_eq(entries.size(), SaveManager.MAX_ENTRIES)
	assert_eq(int(entries[0]["score"]), 100 + (SaveManager.MAX_ENTRIES + 4) * 10,
		"la mejor queda arriba")
	assert_eq(int(entries[SaveManager.MAX_ENTRIES - 1]["score"]), 100 + 5 * 10,
		"y las cinco peores se cayeron")


func test_the_table_shows_the_trophies_of_a_run() -> void:
	SaveManager.clear_leaderboard()
	SaveManager.submit_score(2000, 300.0, 10, "Nyx", [RunRecord.CHAMPION])

	var leaderboard: LeaderboardPanel = _panel("Leaderboard")
	leaderboard.open()
	await wait_frames(2)

	var rows: VBoxContainer = _panel("Leaderboard/Panel/Margin/Layout/Scroll/Rows")
	var chips: Control = rows.get_child(1).get_child(LeaderboardPanel.TROPHY_COLUMN)
	assert_eq(chips.get_child_count(), 1, "una ficha por trofeo")
	assert_eq((chips.get_child(0) as Label).text, RunRecord.get_label(RunRecord.CHAMPION))


## Ocho fichas en una fila de tabla dejan de leerse como logros.
func test_too_many_trophies_collapse_into_a_count() -> void:
	SaveManager.clear_leaderboard()
	var many: Array = []
	for id: StringName in RunRecord.TROPHY_INFO.keys():
		many.append(id)
	SaveManager.submit_score(9000, 300.0, 10, "Nyx", many)

	var leaderboard: LeaderboardPanel = _panel("Leaderboard")
	leaderboard.open()
	await wait_frames(2)

	var rows: VBoxContainer = _panel("Leaderboard/Panel/Margin/Layout/Scroll/Rows")
	var chips: Control = rows.get_child(1).get_child(LeaderboardPanel.TROPHY_COLUMN)
	assert_eq(chips.get_child_count(), LeaderboardPanel.MAX_CHIPS + 1,
		"las que entran, mas el +N")
	var last := chips.get_child(LeaderboardPanel.MAX_CHIPS) as Label
	assert_eq(last.text, "+%d" % (many.size() - LeaderboardPanel.MAX_CHIPS))


func test_saving_a_run_remembers_the_name_for_the_next_one() -> void:
	SaveManager.forget_profiles()
	SaveManager.submit_score(100, 60.0, 2, "Vera")
	assert_eq(SaveManager.get_last_profile(), "VERA")


## Elegir un nombre viejo lo reordena, no lo agrega de nuevo.
func test_a_known_name_moves_to_the_top_instead_of_duplicating() -> void:
	SaveManager.forget_profiles()
	SaveManager.remember_profile("Ana")
	SaveManager.remember_profile("Bolt")
	SaveManager.remember_profile("Ana")

	var profiles: Array[String] = SaveManager.get_profiles()
	assert_eq(profiles.size(), 2, "sin duplicados")
	assert_eq(profiles[0], "ANA", "el ultimo usado va primero")


func test_a_name_that_is_too_short_is_refused() -> void:
	assert_false(SaveManager.is_valid_name("ab"))
	assert_false(SaveManager.is_valid_name("   "))
	assert_true(SaveManager.is_valid_name("abc"))
	assert_eq(SaveManager.sanitize_name("  a very long name indeed  ").length(),
		SaveManager.NAME_MAX_LENGTH, "se recorta, no se rechaza")


func test_the_board_shows_the_name_column() -> void:
	SaveManager.clear_leaderboard()
	SaveManager.submit_score(1200, 240.0, 7, "Juno")

	var leaderboard: LeaderboardPanel = _panel("Leaderboard")
	leaderboard.open()
	await wait_frames(2)

	var rows: VBoxContainer = _panel("Leaderboard/Panel/Margin/Layout/Scroll/Rows")
	var header: Control = rows.get_child(0)
	assert_eq((header.get_child(1) as Label).text, "NAME")
	var row: Control = rows.get_child(1)
	assert_eq((row.get_child(1) as Label).text, "JUNO")
