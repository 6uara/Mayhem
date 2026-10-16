extends GutTest
## La persistencia local: la tabla por arena, los perfiles y los hints vistos.
##
## Los tres archivos viven en `user://` y son de quien juega en esta maquina, asi
## que cada test trabaja sobre una instancia suelta del script -no el autoload- y
## los archivos se guardan tal cual antes y se devuelven despues. El autoload se
## recarga al final para que siga viendo lo mismo que el disco.

const SAVE_MANAGER_SCRIPT: String = "res://scripts/autoload/save_manager.gd"
const OTHER_ARENA: String = "user://arenas/custom.tres"

## path -> contenido original, o null si el archivo no existia.
var _originals: Dictionary = {}
var _save: Node


func before_each() -> void:
	_originals = {}
	for path: String in _paths():
		_originals[path] = FileAccess.get_file_as_string(path) \
			if FileAccess.file_exists(path) else null
		_remove(path)
	_save = load(SAVE_MANAGER_SCRIPT).new()


func after_each() -> void:
	_save.free()
	for path: String in _paths():
		if _originals[path] == null:
			_remove(path)
		else:
			var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
			file.store_string(String(_originals[path]))
			file.close()
	SaveManager.load_leaderboard()
	SaveManager.load_profiles()
	SaveManager.load_tutorial_hints()


func _paths() -> Array[String]:
	return [SaveManager.SAVE_PATH, SaveManager.PROFILES_PATH, SaveManager.TUTORIAL_SAVE_PATH]


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


# ---------------------------------------------------------------- los nombres

## Recortar a NAME_MAX_LENGTH puede cortar justo despues de un espacio. Sin volver
## a limpiar, "ABCDEFGHIJK " y "ABCDEFGHIJK" eran dos perfiles distintos, y la
## tabla mostraba un nombre con un espacio colgando.
func test_a_name_cut_at_a_space_does_not_keep_the_trailing_space() -> void:
	var clean: String = _save.sanitize_name("abcdefghijk lmnop")
	assert_eq(clean, "ABCDEFGHIJK")
	assert_eq(clean, clean.strip_edges())


func test_symbols_are_dropped_and_the_rest_is_kept_in_upper_case() -> void:
	assert_eq(_save.sanitize_name("v3ra!!_x-1"), "V3RA_X-1")


func test_a_name_that_is_only_symbols_is_not_a_name() -> void:
	assert_eq(_save.sanitize_name("!!!???"), "")
	assert_false(_save.is_valid_name("@@ @"))


func test_the_minimum_length_counts_after_cleaning() -> void:
	assert_eq(_save.sanitize_name("a!b"), "", "dos letras validas no alcanzan")
	assert_eq(_save.sanitize_name("abc"), "ABC")


# ---------------------------------------------------------------- la tabla

func test_an_unnamed_run_is_saved_as_the_default_player_and_remembers_no_profile() -> void:
	_save.submit_score(100, 30.0, 1, "")
	assert_eq(String(_save.get_entries()[0]["name"]), SaveManager.DEFAULT_NAME)
	assert_eq(_save.get_profiles().size(), 0, "nadie eligio un nombre: no hay perfil")


## Cada arena tiene sus diez mejores: una arena nueva no le saca lugar a otra.
func test_the_cap_is_per_arena() -> void:
	for i: int in SaveManager.MAX_ENTRIES + 3:
		_save.submit_score(1000 + i, 60.0, 3, "AAA", [], "", "")
	_save.submit_score(5, 60.0, 1, "BBB", [], OTHER_ARENA, "Custom")

	assert_eq(_save.get_entries_for("").size(), SaveManager.MAX_ENTRIES)
	assert_eq(_save.get_entries_for(OTHER_ARENA).size(), 1,
		"la fila peor de todas sobrevive porque es la mejor de su arena")
	assert_eq(int(_save.get_entries_for("")[-1]["score"]), 1003,
		"y de la arena llena se cayeron las tres peores")


func test_the_best_score_can_be_asked_per_arena_or_overall() -> void:
	_save.submit_score(300, 60.0, 3, "AAA")
	_save.submit_score(900, 60.0, 3, "BBB", [], OTHER_ARENA, "Custom")
	assert_eq(_save.get_best_score(), 900)
	assert_eq(_save.get_best_score(SaveManager.DEFAULT_ARENA_ID), 300)
	assert_eq(_save.get_best_score(OTHER_ARENA), 900)
	assert_eq(_save.get_best_score("user://arenas/nadie.tres"), 0)


func test_the_default_arena_is_listed_first_and_the_rest_by_name() -> void:
	_save.submit_score(10, 60.0, 1, "AAA", [], "user://arenas/z.tres", "Zeta")
	_save.submit_score(20, 60.0, 1, "AAA", [], "user://arenas/a.tres", "Alfa")
	_save.submit_score(30, 60.0, 1, "AAA")

	var arenas: Array[Dictionary] = _save.get_arenas()
	var names: Array = arenas.map(func(arena: Dictionary) -> String: return arena["name"])
	assert_eq(names, [SaveManager.DEFAULT_ARENA_NAME, "Alfa", "Zeta"])


func test_trophy_ids_are_saved_as_strings_and_survive_a_reload() -> void:
	_save.submit_score(100, 60.0, 2, "AAA", [&"flawless", &"blitz"])
	_save.load_leaderboard()
	assert_eq(_save.get_entries()[0]["trophies"], ["flawless", "blitz"])


func test_the_mode_survives_a_reload() -> void:
	_save.submit_score(100, 60.0, 2, "AAA", [], "", "", GameManager.Mode.SINGLE_WEAPON)
	_save.load_leaderboard()
	assert_eq(int(_save.get_entries()[0]["mode"]), int(GameManager.Mode.SINGLE_WEAPON))


func test_get_entries_hands_out_copies() -> void:
	_save.submit_score(100, 60.0, 2, "AAA")
	_save.get_entries()[0]["score"] = 999999
	_save.get_entries_for("")[0]["score"] = 999999
	assert_eq(_save.get_best_score(), 100, "editar lo devuelto no toca la tabla")


func test_a_file_that_is_not_a_list_is_ignored() -> void:
	_write(SaveManager.SAVE_PATH, "{\"score\": 10}")
	_save.load_leaderboard()
	assert_eq(_save.get_entries().size(), 0)


## El archivo lo puede editar cualquiera: un archivo con mas de diez filas se
## recorta al leerlo, no al proximo guardado.
func test_a_hand_edited_file_with_too_many_rows_is_capped_on_load() -> void:
	var rows: Array = []
	for i: int in SaveManager.MAX_ENTRIES + 5:
		rows.append({"name": "AAA", "score": i, "time": 1.0, "waves": 1})
	_write(SaveManager.SAVE_PATH, JSON.stringify(rows))
	_save.load_leaderboard()
	assert_eq(_save.get_entries().size(), SaveManager.MAX_ENTRIES)
	assert_eq(_save.get_best_score(), SaveManager.MAX_ENTRIES + 4)


func test_a_row_with_a_bad_arena_falls_back_to_the_default_one() -> void:
	_write(SaveManager.SAVE_PATH, JSON.stringify([
		{"name": "AAA", "score": 10, "time": 1.0, "waves": 1, "arena": 42, "mode": "x"},
	]))
	_save.load_leaderboard()
	var row: Dictionary = _save.get_entries()[0]
	assert_eq(String(row["arena"]), SaveManager.DEFAULT_ARENA_ID)
	assert_eq(String(row["arena_name"]), SaveManager.DEFAULT_ARENA_NAME)
	assert_eq(int(row["mode"]), 0)


# ---------------------------------------------------------------- perfiles

func test_only_the_most_recent_profiles_are_kept() -> void:
	for i: int in SaveManager.MAX_PROFILES + 2:
		_save.remember_profile("P%02d" % i)
	var profiles: Array[String] = _save.get_profiles()
	assert_eq(profiles.size(), SaveManager.MAX_PROFILES)
	assert_eq(profiles[0], "P%02d" % (SaveManager.MAX_PROFILES + 1), "el ultimo primero")
	assert_false(profiles.has("P00"), "el mas viejo se olvida")


func test_profiles_survive_a_reload_in_order() -> void:
	_save.remember_profile("Ana")
	_save.remember_profile("Bolt")
	_save.load_profiles()
	assert_eq(_save.get_profiles(), ["BOLT", "ANA"] as Array[String])
	assert_eq(_save.get_last_profile(), "BOLT")


## Un archivo tocado a mano puede traer cualquier cosa. Un numero o un objeto
## en la lista no puede tirar abajo el arranque del juego.
func test_a_hand_edited_profile_file_keeps_only_valid_names() -> void:
	_write(SaveManager.PROFILES_PATH, JSON.stringify(["ana", 12345, {"x": 1}, "ab", "ANA", "Bolt"]))
	_save.load_profiles()
	assert_eq(_save.get_profiles(), ["ANA", "BOLT"] as Array[String],
		"sin duplicados, sin nombres cortos y sin lo que no es texto")


func test_an_empty_profile_list_has_no_last_profile() -> void:
	assert_eq(_save.get_last_profile(), "")


func test_remembering_an_invalid_name_does_nothing() -> void:
	_save.remember_profile("x")
	assert_eq(_save.get_profiles().size(), 0)


# ---------------------------------------------------------------- hints

func test_hints_survive_a_reload() -> void:
	_save.mark_hint_seen(&"dash")
	_save.mark_hint_seen(&"grapple")
	_save.load_tutorial_hints()
	assert_true(_save.has_seen_hint(&"dash"))
	assert_true(_save.has_seen_hint(&"grapple"))
	assert_false(_save.has_seen_hint(&"slide"))


func test_a_hand_edited_hint_file_with_junk_does_not_crash_the_load() -> void:
	_write(SaveManager.TUTORIAL_SAVE_PATH, JSON.stringify(["dash", 7, {"a": 1}, null]))
	_save.load_tutorial_hints()
	assert_true(_save.has_seen_hint(&"dash"))
	_write(SaveManager.TUTORIAL_SAVE_PATH, "{}")
	_save.load_tutorial_hints()
	assert_false(_save.has_seen_hint(&"dash"), "un archivo que no es lista se ignora")


## Borrar puntajes no puede olvidar quien sos ni los hints, y al reves: son tres
## archivos con tres vidas distintas.
func test_clearing_one_store_leaves_the_other_two_alone() -> void:
	_save.submit_score(100, 60.0, 2, "Ana")
	_save.mark_hint_seen(&"dash")
	_save.clear_leaderboard()
	assert_eq(_save.get_profiles(), ["ANA"] as Array[String])
	assert_true(_save.has_seen_hint(&"dash"))

	_save.submit_score(100, 60.0, 2, "Ana")
	_save.clear_tutorial_hints()
	assert_eq(_save.get_entries().size(), 1)
	_save.forget_profiles()
	assert_eq(_save.get_entries().size(), 1)
