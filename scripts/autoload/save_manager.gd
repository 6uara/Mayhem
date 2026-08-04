extends Node
## Local leaderboard persistence. Holds no gameplay state.
## Nothing carries between runs - there is no meta-progression in the slice.

## Tokens.LEADERBOARD_PATH. JSON rather than ConfigFile because the handoff
## names the file, and a leaderboard is a list rather than a settings tree.
const SAVE_PATH: String = "user://leaderboard.json"
const MAX_ENTRIES: int = 10  ## Tokens.LEADERBOARD_ENTRIES

## Array of { "score": int, "time": float, "waves": int, "date": String }
var _entries: Array[Dictionary] = []


func _ready() -> void:
	load_leaderboard()


# Public API

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
