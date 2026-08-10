extends Node
## Local leaderboard persistence, plus which first-time tutorial hints have
## already been shown. Neither is gameplay state: the leaderboard is a list of
## past runs, and "has this hint been seen" is a UI courtesy, not
## meta-progression - no purchase, unlock or stat carries between runs.

## Tokens.LEADERBOARD_PATH. JSON rather than ConfigFile because the handoff
## names the file, and a leaderboard is a list rather than a settings tree.
const SAVE_PATH: String = "user://leaderboard.json"
const MAX_ENTRIES: int = 10  ## Tokens.LEADERBOARD_ENTRIES

## Separate file from the leaderboard on purpose - two independent concerns
## with independent lifetimes ("clear my scores" should never also reset hints,
## or vice versa).
const TUTORIAL_SAVE_PATH: String = "user://tutorial.json"

## Array of { "score": int, "time": float, "waves": int, "date": String }
var _entries: Array[Dictionary] = []
## Set of hint ids already shown, ever: StringName -> true.
var _seen_hints: Dictionary = {}


func _ready() -> void:
	load_leaderboard()
	load_tutorial_hints()


# Public API - leaderboard

func submit_score(score: int, total_time: float, waves_cleared: int) -> void:
	_entries.push_back({
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
		if entry is Dictionary:
			_entries.push_back(entry)


func save_leaderboard() -> void:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot write %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(_entries, "	"))


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
