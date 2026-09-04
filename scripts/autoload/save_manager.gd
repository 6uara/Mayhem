extends Node
## Local leaderboard persistence, plus which first-time tutorial hints have
## already been shown. Neither is gameplay state: the leaderboard is a list of
## past runs, and "has this hint been seen" is a UI courtesy, not
## meta-progression - no purchase, unlock or stat carries between runs.

## Tokens.LEADERBOARD_PATH. JSON rather than ConfigFile because the handoff
## names the file, and a leaderboard is a list rather than a settings tree.
const SAVE_PATH: String = "user://leaderboard.json"
## Veinte y no diez desde que las filas llevan nombre: con dos o tres personas
## turnandose en la misma maquina, diez lugares los llena el mejor de todos y el
## resto no vuelve a verse nunca en la tabla.
const MAX_ENTRIES: int = 20

## Los nombres que ya se usaron en esta maquina. Archivo aparte, por el mismo
## criterio que separa el leaderboard de los hints: "borrame los puntajes" no
## puede olvidarse tambien quien sos.
const PROFILES_PATH: String = "user://profiles.json"
## Con el que se guarda una run cuyo nombre nadie eligio - y con el que se leen
## las entradas escritas antes de que existieran los nombres.
const DEFAULT_NAME: String = "PLAYER"
const NAME_MIN_LENGTH: int = 3
const NAME_MAX_LENGTH: int = 12
## Cuantos nombres se recuerdan. Es una lista para elegir, no un padron.
const MAX_PROFILES: int = 8

## Separate file from the leaderboard on purpose - two independent concerns
## with independent lifetimes ("clear my scores" should never also reset hints,
## or vice versa).
const TUTORIAL_SAVE_PATH: String = "user://tutorial.json"

## Array of { "name": String, "score": int, "time": float, "waves": int,
## "date": String }
var _entries: Array[Dictionary] = []
## Nombres usados, del mas reciente al mas viejo.
var _profiles: Array[String] = []
## Set of hint ids already shown, ever: StringName -> true.
var _seen_hints: Dictionary = {}


func _ready() -> void:
	load_leaderboard()
	load_profiles()
	load_tutorial_hints()


# Public API - leaderboard

## Guardar tambien recuerda el nombre: la lista de perfiles es un efecto de
## haber jugado, no una pantalla de alta aparte.
func submit_score(score: int, total_time: float, waves_cleared: int,
		player_name: String = DEFAULT_NAME) -> void:
	var final_name: String = sanitize_name(player_name)
	if final_name == "":
		final_name = DEFAULT_NAME
	else:
		remember_profile(final_name)
	_entries.push_back({
		"name": final_name,
		"score": score,
		"time": total_time,
		"waves": waves_cleared,
		"date": Time.get_datetime_string_from_system(false, true),
	})
	_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["score"]) > int(b["score"]))
	if _entries.size() > MAX_ENTRIES:
		_entries.resize(MAX_ENTRIES)
	save_leaderboard()


func get_entries() -> Array[Dictionary]:
	return _entries.duplicate(true)


func get_best_score() -> int:
	if _entries.is_empty():
		return 0
	return int(_entries[0]["score"])


func clear_leaderboard() -> void:
	_entries.clear()
	save_leaderboard()


func load_leaderboard() -> void:
	_entries.clear()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("SaveManager: cannot read %s" % SAVE_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		push_warning("SaveManager: %s is not a leaderboard, ignoring it" % SAVE_PATH)
		return
	for entry: Variant in parsed:
		if not entry is Dictionary:
			continue
		var row: Dictionary = entry
		# Las entradas guardadas antes de que existieran los nombres siguen
		# siendo runs validas: se leen con el nombre por defecto en vez de
		# desaparecer de la tabla.
		if not row.has("name"):
			row["name"] = DEFAULT_NAME
		_entries.push_back(row)


func save_leaderboard() -> void:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot write %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(_entries, "	"))


# Public API - perfiles

## Los nombres conocidos, el ultimo usado primero.
func get_profiles() -> Array[String]:
	return _profiles.duplicate()


func get_last_profile() -> String:
	return _profiles[0] if not _profiles.is_empty() else ""


## Sube el nombre al tope de la lista. Sin duplicados: elegir un nombre viejo lo
## reordena, no lo agrega otra vez.
func remember_profile(player_name: String) -> void:
	var clean: String = sanitize_name(player_name)
	if clean == "":
		return
	_profiles.erase(clean)
	_profiles.push_front(clean)
	if _profiles.size() > MAX_PROFILES:
		_profiles.resize(MAX_PROFILES)
	save_profiles()


func forget_profiles() -> void:
	_profiles.clear()
	save_profiles()


## El nombre normalizado, o vacio si no da. Un solo lugar decide que es un
## nombre valido, asi que el panel que lo pide y el archivo que lo guarda no
## pueden opinar distinto.
func sanitize_name(raw: String) -> String:
	var out: String = ""
	for character: String in raw.strip_edges():
		if character.is_valid_identifier() or character.is_valid_int() 				or character == " " or character == "_" or character == "-":
			out += character
	out = out.strip_edges()
	if out.length() < NAME_MIN_LENGTH:
		return ""
	return out.substr(0, NAME_MAX_LENGTH).to_upper()


func is_valid_name(raw: String) -> bool:
	return sanitize_name(raw) != ""


func load_profiles() -> void:
	_profiles.clear()
	if not FileAccess.file_exists(PROFILES_PATH):
		return
	var file: FileAccess = FileAccess.open(PROFILES_PATH, FileAccess.READ)
	if file == null:
		push_error("SaveManager: cannot read %s" % PROFILES_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		push_warning("SaveManager: %s is not a profile list, ignoring it" % PROFILES_PATH)
		return
	for name_value: Variant in parsed:
		var clean: String = sanitize_name(String(name_value))
		if clean != "" and not _profiles.has(clean):
			_profiles.push_back(clean)


func save_profiles() -> void:
	var file: FileAccess = FileAccess.open(PROFILES_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot write %s" % PROFILES_PATH)
		return
	file.store_string(JSON.stringify(_profiles, "	"))


# Public API - tutorial hints

func has_seen_hint(id: StringName) -> bool:
	return bool(_seen_hints.get(id, false))


func mark_hint_seen(id: StringName) -> void:
	if has_seen_hint(id):
		return
	_seen_hints[id] = true
	save_tutorial_hints()


## Lets a player (or a playtest wrangler resetting the build between testers)
## see every hint again from a clean slate.
func clear_tutorial_hints() -> void:
	_seen_hints.clear()
	save_tutorial_hints()


func load_tutorial_hints() -> void:
	_seen_hints.clear()
	if not FileAccess.file_exists(TUTORIAL_SAVE_PATH):
		return
	var file: FileAccess = FileAccess.open(TUTORIAL_SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("SaveManager: cannot read %s" % TUTORIAL_SAVE_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		push_warning("SaveManager: %s is not a hint list, ignoring it" % TUTORIAL_SAVE_PATH)
		return
	for id: Variant in parsed:
		_seen_hints[StringName(id)] = true


func save_tutorial_hints() -> void:
	var file: FileAccess = FileAccess.open(TUTORIAL_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot write %s" % TUTORIAL_SAVE_PATH)
		return
	var ids: Array = _seen_hints.keys().map(func(id: StringName) -> String: return String(id))
	file.store_string(JSON.stringify(ids, "	"))
