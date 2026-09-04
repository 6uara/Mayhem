extends GutTest
## La pantalla que le pregunta al jugador con que nombre queda anotada la run.
##
## Antes de esto el puntaje se guardaba solo, en silencio, sin nombre y solo al
## ganar: la tabla era una lista de numeros anonimos que ademas casi nunca se
## llenaba, porque perder no dejaba rastro.

const OVERLAY_SCENE: String = "res://scenes/ui/match_overlay.tscn"

var _overlay: CanvasLayer
var _panel: ScoreEntryPanel
var _saved: Array[Dictionary] = []
var _saved_profiles: Array[String] = []


func before_each() -> void:
	_saved = SaveManager.get_entries()
	_saved_profiles = SaveManager.get_profiles()
	SaveManager.clear_leaderboard()
	SaveManager.forget_profiles()
	_overlay = add_child_autofree(load(OVERLAY_SCENE).instantiate())
	await wait_frames(2)
	_panel = _overlay.get_node("ScoreEntry")


func after_each() -> void:
	SaveManager.clear_leaderboard()
	for entry: Dictionary in _saved:
		SaveManager.submit_score(int(entry.get("score", 0)),
			float(entry.get("time", 0.0)), int(entry.get("waves", 0)),
			String(entry.get("name", SaveManager.DEFAULT_NAME)))
	SaveManager.forget_profiles()
	for index: int in range(_saved_profiles.size() - 1, -1, -1):
		SaveManager.remember_profile(_saved_profiles[index])


func _end_panel() -> Control:
	return _overlay.get_node("EndPanel")


func _name_edit() -> LineEdit:
	return _panel.get_node("Panel/Margin/Layout/NameEdit")


func _profiles() -> OptionButton:
	return _panel.get_node("Panel/Margin/Layout/Profiles")


func _save_button() -> Button:
	return _panel.get_node("Panel/Margin/Layout/Footer/SaveButton")


func _skip_button() -> Button:
	return _panel.get_node("Panel/Margin/Layout/Footer/SkipButton")


func test_finishing_a_run_asks_for_the_name_before_the_end_screen() -> void:
	EventBus.run_finished.emit(2500, 300.0, 10, true)
	await wait_frames(2)

	assert_true(_panel.visible, "primero el nombre")
	assert_false(_end_panel().visible,
		"la pantalla de fin muestra el Best, y todavia no hay nada que anotar")


## Perder tambien es terminar una run. Antes no dejaba puntaje ninguno, asi que
## la tabla solo podia listar a quien se pasara las diez waves.
func test_dying_also_records_a_run() -> void:
	EventBus.run_finished.emit(800, 140.0, 6, false)
	await wait_frames(2)
	_name_edit().text = "Rook"
	_save_button().pressed.emit()
	await wait_frames(2)

	var entries: Array[Dictionary] = SaveManager.get_entries()
	assert_eq(entries.size(), 1, "una derrota es una run anotable")
	assert_eq(String(entries[0].get("name", "")), "ROOK")
	assert_eq(int(entries[0].get("waves", -1)), 6, "las waves que limpio de verdad")


func test_saving_the_name_reveals_the_end_screen() -> void:
	EventBus.run_finished.emit(2500, 300.0, 10, true)
	await wait_frames(2)
	_name_edit().text = "Vega"
	_save_button().pressed.emit()
	await wait_frames(2)

	assert_false(_panel.visible)
	assert_true(_end_panel().visible)
	var details: Label = _overlay.get_node("EndPanel/VBox/Details")
	assert_string_contains(details.text, "Best 2500",
		"el mejor puntaje que muestra la pantalla ya incluye esta run")


## Saltar no tira la partida: anota con el nombre por defecto. Un puntaje perdido
## molesta mas que una fila que dice PLAYER.
func test_skipping_still_records_the_run() -> void:
	EventBus.run_finished.emit(1500, 200.0, 8, true)
	await wait_frames(2)
	_skip_button().pressed.emit()
	await wait_frames(2)

	var entries: Array[Dictionary] = SaveManager.get_entries()
	assert_eq(entries.size(), 1)
	assert_eq(String(entries[0].get("name", "")), SaveManager.DEFAULT_NAME)


## En una maquina nueva no hay lista que ofrecer: se va derecho al campo.
func test_the_first_run_ever_goes_straight_to_typing() -> void:
	EventBus.run_finished.emit(100, 60.0, 1, false)
	await wait_frames(2)

	assert_false(_profiles().visible, "no hay nombres conocidos todavia")
	assert_true(_name_edit().visible)


## Y cuando los hay, elegir uno es un clic y no volver a tipearlo entero.
func test_a_known_name_can_be_picked_from_the_list() -> void:
	SaveManager.remember_profile("Iris")
	EventBus.run_finished.emit(700, 90.0, 4, false)
	await wait_frames(2)

	assert_true(_profiles().visible)
	assert_false(_name_edit().visible, "con un nombre elegido no hay nada que escribir")
	_save_button().pressed.emit()
	await wait_frames(2)

	assert_eq(String(SaveManager.get_entries()[0].get("name", "")), "IRIS")


## El boton apagado es el aviso: el jugador tiene que ver que le falta mientras
## escribe, no despues de apretar.
func test_save_stays_disabled_until_the_name_is_valid() -> void:
	EventBus.run_finished.emit(400, 80.0, 2, false)
	await wait_frames(2)

	_name_edit().text = "ab"
	_name_edit().text_changed.emit("ab")
	assert_true(_save_button().disabled, "dos letras no alcanzan")

	_name_edit().text = "abc"
	_name_edit().text_changed.emit("abc")
	assert_false(_save_button().disabled)
