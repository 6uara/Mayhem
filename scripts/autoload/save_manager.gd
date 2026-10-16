extends Node
## Local leaderboard persistence, plus which first-time tutorial hints have
## already been shown. Neither is gameplay state: the leaderboard is a list of
## past runs, and "has this hint been seen" is a UI courtesy, not
## meta-progression - no purchase, unlock or stat carries between runs.

## Tokens.LEADERBOARD_PATH. JSON rather than ConfigFile because the handoff
## names the file, and a leaderboard is a list rather than a settings tree.
const SAVE_PATH: String = "user://leaderboard.json"
## Diez, y no las veinte que hubo un tiempo.
##
## Veinte se eligio cuando las filas empezaron a llevar nombre, para que en una
## maquina compartida el mejor de todos no llenara la tabla entero. El costo de
## esa decision fue una tabla que nadie lee hasta el final: veinte filas de tres
## numeros son una planilla, y la fila quince no significa nada para nadie.
##
## Diez vuelve a hacer que entrar a la tabla sea un logro, que es de lo que vive
## una tabla local. Lo que compensa el lugar que se pierde son los trofeos: una
## fila ahora cuenta **como** fue esa run, asi que diez filas dicen mas de lo que
## decian veinte.
const MAX_ENTRIES: int = 10

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

## La tabla es por arena: cada arena tiene sus diez mejores.
##
## Con el editor de arenas, una arena hecha a medida -sin enemigos que lleguen,
## con pads por todos lados- competia en la misma tabla que la del juego. Las
## filas guardan en que arena se jugaron, y las que se guardaron antes de esto
## son de la arena por defecto, que era la unica.
const DEFAULT_ARENA_ID: String = "res://data/arenas/default_arena.tres"
const DEFAULT_ARENA_NAME: String = "The Pit"

## Array of { "name": String, "score": int, "time": float, "waves": int,
## "date": String, "trophies": Array[String], "arena": String,
## "arena_name": String, "mode": int }
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
## Los trofeos viajan con la fila y no en un archivo de logros aparte: en un
## juego sin meta-progresion, un trofeo es la marca de **esa** run, y se va con
## ella cuando la fila cae de la tabla. Ver RunRecord.
func submit_score(score: int, total_time: float, waves_cleared: int,
		player_name: String = DEFAULT_NAME,
		trophies: Array = [], arena_id: String = "", arena_name: String = "",
		mode: int = 0) -> void:
	var final_name: String = sanitize_name(player_name)
	if final_name == "":
		final_name = DEFAULT_NAME
	else:
		remember_profile(final_name)
	# A String y no StringName: lo que sale de aca se escribe como JSON, y un
	# StringName vuelve del archivo como String igual.
	var trophy_ids: Array = []
	for id: Variant in trophies:
		trophy_ids.append(String(id))
	_entries.push_back({
		"name": final_name,
		"score": score,
		"time": total_time,
		"waves": waves_cleared,
		"date": Time.get_datetime_string_from_system(false, true),
		"trophies": trophy_ids,
		"arena": arena_id if arena_id != "" else DEFAULT_ARENA_ID,
		"arena_name": arena_name if arena_name != "" else DEFAULT_ARENA_NAME,
		"mode": mode,
	})
	_sort_and_cap()
	save_leaderboard()


## Todas las filas, de todas las arenas, de mayor a menor.
func get_entries() -> Array[Dictionary]:
	return _entries.duplicate(true)


## Las filas de una arena, de mayor a menor.
func get_entries_for(arena_id: String) -> Array[Dictionary]:
	var key: String = arena_id if arena_id != "" else DEFAULT_ARENA_ID
	var out: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		if String(entry["arena"]) == key:
			out.push_back(entry.duplicate(true))
	return out


## Las arenas que tienen al menos una fila, como [{id, name}], la default primero.
func get_arenas() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	for entry: Dictionary in _entries:
		var id: String = String(entry["arena"])
		if seen.has(id):
			continue
		seen[id] = true
		out.push_back({"id": id, "name": String(entry["arena_name"])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["id"] == DEFAULT_ARENA_ID:
			return true
		if b["id"] == DEFAULT_ARENA_ID:
			return false
		return String(a["name"]) < String(b["name"]))
	return out


## El mejor de una arena; sin arena, el mejor de todas.
func get_best_score(arena_id: String = "") -> int:
	var rows: Array[Dictionary] = _entries if arena_id == "" else get_entries_for(arena_id)
	if rows.is_empty():
		return 0
	return int(rows[0]["score"])


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
		var row: Dictionary = _read_row(entry)
		if not row.is_empty():
			_entries.push_back(row)
	# El archivo lo puede editar cualquiera: no se confia en que venga ordenado
	# ni en que respete el tope.
	_sort_and_cap()


## Ordena de mayor a menor y deja `MAX_ENTRIES` por arena: una arena nueva no le
## saca lugar a otra.
func _sort_and_cap() -> void:
	_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["score"]) > int(b["score"]))
	var per_arena: Dictionary = {}
	var kept: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		var id: String = String(entry["arena"])
		var count: int = int(per_arena.get(id, 0))
		if count >= MAX_ENTRIES:
			continue
		per_arena[id] = count + 1
		kept.push_back(entry)
	_entries = kept


## Una fila del archivo, validada. Vacia si no se puede leer como una run.
##
## `user://leaderboard.json` es un archivo que el jugador puede tocar a mano. Una
## fila sin `score` cargaba bien y reventaba despues, en el sort de
## `submit_score()` o en `get_best_score()`. Lo imprescindible para ordenar y
## mostrar (puntaje, tiempo, oleadas) tiene que ser un numero; lo demas se
## completa con su valor por defecto.
func _read_row(entry: Variant) -> Dictionary:
	if not entry is Dictionary:
		return {}
	var raw: Dictionary = entry
	for key: String in ["score", "time", "waves"]:
		var value: Variant = raw.get(key)
		if not (value is int or value is float):
			return {}
	# Las entradas guardadas antes de que existieran los nombres siguen siendo
	# runs validas: se leen con el nombre por defecto en vez de desaparecer.
	var name_value: Variant = raw.get("name")
	var row_name: String = sanitize_name(name_value) if name_value is String else ""
	# Lo mismo para las runs anteriores a los trofeos: una run sin trofeos y una
	# de antes de que existieran se ven igual, que es lo correcto.
	var trophies: Array = []
	var trophy_value: Variant = raw.get("trophies")
	if trophy_value is Array:
		for id: Variant in trophy_value:
			if id is String:
				trophies.append(id)
	var date_value: Variant = raw.get("date")
	# Las filas de antes de la tabla por arena son de la unica arena que habia.
	var arena_value: Variant = raw.get("arena")
	var arena_name_value: Variant = raw.get("arena_name")
	var mode_value: Variant = raw.get("mode")
	return {
		"arena": arena_value if arena_value is String and arena_value != "" 			else DEFAULT_ARENA_ID,
		"arena_name": arena_name_value if arena_name_value is String 			and arena_name_value != "" else DEFAULT_ARENA_NAME,
		"mode": int(mode_value) if (mode_value is int or mode_value is float) else 0,
		"name": row_name if row_name != "" else DEFAULT_NAME,
		"score": int(raw["score"]),
		"time": float(raw["time"]),
		"waves": int(raw["waves"]),
		"date": date_value if date_value is String else "",
		"trophies": trophies,
	}


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
	# Se recorta y despues se limpia: el corte puede caer justo despues de un
	# espacio, y "ABCDEFGHIJK " seria otro perfil que "ABCDEFGHIJK". El minimo se
	# mide sobre lo que queda.
	out = out.strip_edges().substr(0, NAME_MAX_LENGTH).strip_edges()
	if out.length() < NAME_MIN_LENGTH:
		return ""
	return out.to_upper()


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
		# El archivo se puede editar a mano: lo que no es texto no es un nombre, y
		# `String()` sobre un numero o un objeto no es una conversion valida.
		if not name_value is String:
			continue
		var clean: String = sanitize_name(name_value)
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
		# Igual que los perfiles: una entrada que no es un id se descarta.
		if id is String:
			_seen_hints[StringName(id)] = true


func save_tutorial_hints() -> void:
	var file: FileAccess = FileAccess.open(TUTORIAL_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot write %s" % TUTORIAL_SAVE_PATH)
		return
	var ids: Array = _seen_hints.keys().map(func(id: StringName) -> String: return String(id))
	file.store_string(JSON.stringify(ids, "	"))
