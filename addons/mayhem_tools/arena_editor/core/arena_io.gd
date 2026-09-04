@tool
class_name ArenaIO
extends RefCounted
## Reading and writing arenas. Resource is the native format - free
## serialization, inspector integration, typed on load - and JSON is the
## explicit export, so an arena stays diffable in git and passable by hand.

const RESOURCE_EXTENSION: String = "tres"
const JSON_EXTENSION: String = "json"
const ARENA_DIR: String = "res://data/arenas"


static func save(arena: ArenaData, path: String) -> Error:
	if arena == null:
		return ERR_INVALID_PARAMETER
	arena.format_version = ArenaData.CURRENT_FORMAT_VERSION
	if path.get_extension().to_lower() == JSON_EXTENSION:
		return save_json(arena, path)
	return ResourceSaver.save(arena, path)


static func load_arena(path: String) -> ArenaData:
	if path.get_extension().to_lower() == JSON_EXTENSION:
		return load_json(path)
	var resource: Resource = ResourceLoader.load(path, "ArenaData", ResourceLoader.CACHE_MODE_IGNORE)
	var arena := resource as ArenaData
	if arena == null:
		push_error("ArenaIO: '%s' is not an arena." % path)
		return null
	if arena.format_version != ArenaData.CURRENT_FORMAT_VERSION:
		arena = ArenaData.from_dict(arena.to_dict())  # Runs the migration chain.
	return arena


static func save_json(arena: ArenaData, path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(arena.to_json())
	file.close()
	return OK


static func load_json(path: String) -> ArenaData:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ArenaIO: could not open '%s'." % path)
		return null
	var arena: ArenaData = ArenaData.from_json(file.get_as_text())
	file.close()
	return arena


static func list_arenas(dir_path: String = ARENA_DIR) -> PackedStringArray:
	var out := PackedStringArray()
	for file_name: String in DirAccess.get_files_at(dir_path):
		var clean: String = file_name.trim_suffix(".remap")
		var extension: String = clean.get_extension().to_lower()
		if extension == RESOURCE_EXTENSION or extension == JSON_EXTENSION:
			out.append(dir_path.path_join(clean))
	return out
