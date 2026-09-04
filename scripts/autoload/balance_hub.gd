extends Node
## Live tuning. Watches the balance resources on disk and reloads them in place
## while the game runs, so a value changed in the Balance Editor lands in the
## current match instead of waiting for a restart.
##
## Reloading with CACHE_MODE_REPLACE is what makes this cheap: every system that
## already holds `economy_config.tres` or an archetype's `EnemyData` keeps its
## reference and simply sees the new numbers. Nothing had to subscribe.
##
## Editor builds only. An exported game has no writable resource files to watch
## and paying for the polling would be pointless.

signal balance_changed()

const WATCHED_DIRS: Array[String] = [
	"res://data/economy",
	"res://data/enemies",
]
## Seconds between checks. Fast enough to feel live, slow enough to be free.
const POLL_INTERVAL: float = 0.5

var _timestamps: Dictionary = {}
var _elapsed: float = 0.0


func _ready() -> void:
	if not OS.has_feature("editor"):
		set_process(false)
		return
	for path: String in _watched_files():
		_timestamps[path] = FileAccess.get_modified_time(path)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < POLL_INTERVAL:
		return
	_elapsed = 0.0
	var reloaded: bool = false
	for path: String in _watched_files():
		var stamp: int = FileAccess.get_modified_time(path)
		if int(_timestamps.get(path, 0)) == stamp:
			continue
		_timestamps[path] = stamp
		ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
		reloaded = true
	if reloaded:
		balance_changed.emit()


# Private

func _watched_files() -> Array[String]:
	var files: Array[String] = []
	for dir_path: String in WATCHED_DIRS:
		for file_name: String in DirAccess.get_files_at(dir_path):
			var clean: String = file_name.trim_suffix(".remap")
			if clean.get_extension().to_lower() == "tres":
				files.append(dir_path.path_join(clean))
	return files
