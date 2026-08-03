extends Node
## Local leaderboard persistence. Holds no gameplay state.
## Nothing carries between runs - there is no meta-progression in the slice.

const SAVE_PATH: String = "user://leaderboard.cfg"
const MAX_ENTRIES: int = 20

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
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	if not config.has_section("entries"):
		return
	for key: String in config.get_section_keys("entries"):
		var entry: Variant = config.get_value("entries", key, null)
		if entry is Dictionary:
			_entries.push_back(entry)


func save_leaderboard() -> void:
	var config := ConfigFile.new()
	for i: int in _entries.size():
		config.set_value("entries", "entry_%02d" % i, _entries[i])
	var error: int = config.save(SAVE_PATH)
	if error != OK:
		push_error("SaveManager: failed to save leaderboard (%d)" % error)
