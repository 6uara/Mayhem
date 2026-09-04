extends Node
## The arena a player is building or playing, and where those files live.
##
## The addon's `ArenaData`, validator and loader do not know the game exists, and
## the game does not know the editor exists. This is the one object that knows
## both: it owns the arena in hand, the `user://` folder it is saved to, and the
## round trip out to a playtest and back.

signal arena_changed()

const CATALOG_PATH: String = "res://data/arena_pieces/default_catalog.tres"
## El playtest entra por la escena de partida de siempre: `ArenaHost` mira esta
## sesion y carga la arena en mano en vez de la default.
const GAME_SCENE: String = "res://scenes/main/game.tscn"
const EDITOR_SCENE: String = "res://scenes/main/arena_editor.tscn"
## Player-made arenas live beside the save file, not in the project: an exported
## game cannot write to res://, and these are the player's files anyway.
const USER_DIR: String = "user://arenas"
## Arenas that ship with the game, the default one among them.
const SHIPPED_DIR: String = "res://data/arenas"
const EXTENSION: String = "tres"

var catalog: PieceCatalog

## The arena being edited. Never null once ready: an empty one is still an arena.
var arena: ArenaData
## Where `arena` was last saved or loaded from. Empty means it has never been.
var current_path: String = ""
## True while a playtest launched from the editor is running, which is what puts
## "Back to the editor" in the pause menu instead of only "Quit to menu".
var is_playtesting: bool = false
## The arena the next normal run happens in, chosen from the Play screen. Empty
## means "whatever the game scene calls its default".
var run_arena_path: String = ""


func _ready() -> void:
	catalog = load(CATALOG_PATH) as PieceCatalog
	if catalog == null:
		push_error("ArenaSession: no piece catalog at %s" % CATALOG_PATH)
	arena = new_arena()


# Arenas

func new_arena(grid_size: Vector3i = ArenaData.FIXED_SIZE) -> ArenaData:
	var fresh := ArenaData.new()
	fresh.arena_name = "New Arena"
	fresh.grid_size = grid_size
	fresh.created_at = Time.get_datetime_string_from_system(true)
	arena = fresh
	current_path = ""
	arena_changed.emit()
	return fresh


## Shrinking the grid must not strand pieces outside it. Answered here rather
## than in the screen so the rule is testable and both editors can ask it.
func can_resize(size: Vector3i) -> bool:
	for entry: PlacementEntry in arena.placements:
		var piece: PieceDefinition = catalog.get_piece(entry.piece_id)
		if piece == null:
			continue
		for offset: Vector3i in piece.get_footprint(entry.rotation):
			var cell: Vector3i = entry.cell + offset
			if cell.x >= size.x or cell.y >= size.y or cell.z >= size.z:
				return false
	return true


## Returns false and changes nothing when a piece would be left outside.
func resize(size: Vector3i) -> bool:
	if not can_resize(size):
		return false
	arena.grid_size = size
	arena_changed.emit()
	return true


## Always writes inside `user://arenas`, whatever was opened. Loading one of the
## example arenas that ship in `res://` and pressing SAVE has to produce a copy
## of the player's own - an exported game cannot write to res:// at all, and even
## in the editor overwriting shipped content from the in-game editor is wrong.
func save(target_path: String = "") -> Error:
	if arena == null:
		return ERR_INVALID_DATA
	var path: String = target_path if target_path != "" else current_path
	if path == "" or not path.begins_with(USER_DIR):
		path = path_for_name(arena.arena_name)
	ensure_dir()
	var error: Error = ArenaIO.save(arena, path)
	if error == OK:
		current_path = path
	return error


func load_arena(path: String) -> bool:
	var loaded: ArenaData = ArenaIO.load_arena(path)
	if loaded == null:
		return false
	arena = loaded
	current_path = path
	arena_changed.emit()
	return true


## Arena files the player has, newest first, so the load list opens on the one
## they were just working on.
func list_arenas() -> PackedStringArray:
	ensure_dir()
	var paths: Array[String] = []
	for file_name: String in DirAccess.get_files_at(USER_DIR):
		if file_name.get_extension().to_lower() in [EXTENSION, "json"]:
			paths.append(USER_DIR.path_join(file_name))
	paths.sort_custom(func(a: String, b: String) -> bool:
		return FileAccess.get_modified_time(a) > FileAccess.get_modified_time(b))
	var out := PackedStringArray()
	for path: String in paths:
		out.append(path)
	return out


## Everything a player can press Play on: what ships with the game plus what they
## built. One entry per file, shipped first, each with the name the arena calls
## itself rather than its filename.
func list_playable() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for path: String in _arenas_in(SHIPPED_DIR):
		entries.append(_describe(path, true))
	for path: String in list_arenas():
		entries.append(_describe(path, false))
	return entries


## The arena the next run uses, or null for the game scene's own default.
func get_run_arena() -> ArenaData:
	if run_arena_path == "":
		return null
	return ArenaIO.load_arena(run_arena_path)


func set_run_arena(path: String) -> void:
	run_arena_path = path


func delete_arena(path: String) -> Error:
	var error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if error == OK and path == current_path:
		current_path = ""
	if error == OK and path == run_arena_path:
		run_arena_path = ""
	return error


func _arenas_in(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir_path):
		return out
	for file_name: String in DirAccess.get_files_at(dir_path):
		var clean: String = file_name.trim_suffix(".remap")
		if clean.get_extension().to_lower() in [EXTENSION, "json"]:
			out.append(dir_path.path_join(clean))
	return out


## Reads the file for its name and size. Cheap enough for a menu list, and the
## alternative is showing the player "default_arena.tres".
func _describe(path: String, is_shipped: bool) -> Dictionary:
	var arena: ArenaData = ArenaIO.load_arena(path)
	var arena_name: String = path.get_file().get_basename().capitalize()
	var pieces: int = 0
	if arena != null:
		pieces = arena.placements.size()
		if arena.arena_name.strip_edges() != "":
			arena_name = arena.arena_name
	return {
		"path": path,
		"name": arena_name,
		"pieces": pieces,
		"shipped": is_shipped,
	}


## `user://arenas/my_arena.tres`, from whatever the player typed as a name.
func path_for_name(arena_name: String) -> String:
	var slug: String = arena_name.strip_edges().to_snake_case().validate_filename()
	if slug == "":
		slug = "arena"
	return USER_DIR.path_join("%s.%s" % [slug, EXTENSION])


func ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(USER_DIR):
		DirAccess.make_dir_recursive_absolute(USER_DIR)


# Validation and playtest

func validate() -> Array[ValidationIssue]:
	return ArenaValidator.validate(arena, catalog)


func is_playable() -> bool:
	return ArenaValidator.errors(validate()).is_empty()


## Leaves the editor for a real match in the arena in hand. Refuses a broken
## arena, so a validation error can never reach the loader.
func playtest() -> bool:
	if not is_playable():
		return false
	is_playtesting = true
	GameManager.open_scene(GAME_SCENE, GameManager.State.PLAYING)
	return true


## Back to the editor with the arena intact - it never left memory, so nothing
## has to be reloaded and unsaved work survives the trip.
func return_to_editor() -> void:
	is_playtesting = false
	GameManager.open_scene(EDITOR_SCENE)


func open_editor() -> void:
	GameManager.open_scene(EDITOR_SCENE)
