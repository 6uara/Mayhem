@tool
class_name ArenaData
extends Resource
## A saved arena. The editor writes it, the game reads it, and neither knows
## anything about the other beyond this shape.

## Bumped whenever the on-disk shape changes; `_migrate` carries older files up.
const CURRENT_FORMAT_VERSION: int = 4

## El unico tamano que tiene una arena. Era una eleccion de tres presets y dejo
## de serlo: una arena chica es una arena donde el grapple no llega a ningun
## lado y donde la horda te acorrala en la wave cuatro, y el juego se balanceo
## contra la grande. Un tamano fijo tambien es una cosa menos que validar, que
## enmarcar y que explicarle a alguien que abre el editor por primera vez.
const FIXED_SIZE: Vector3i = Vector3i(32, 8, 32)

## Sigue siendo un diccionario, con una sola entrada, porque las dos interfaces
## del editor lo listan y porque el dia que vuelva a haber mas de un tamano el
## unico cambio es esta constante.
const SIZE_PRESETS: Dictionary = {
	"Large  32x8x32": FIXED_SIZE,
}

@export var format_version: int = CURRENT_FORMAT_VERSION
@export var arena_name: String = ""
@export var grid_size: Vector3i = FIXED_SIZE
@export var placements: Array[PlacementEntry] = []
@export var player_spawn: Vector3i = Vector3i.ZERO
@export var has_player_spawn: bool = false
@export var enemy_spawns: Array[EnemySpawnEntry] = []
## Which venue surrounds the grid. See `ArenaTheme`.
@export var theme_id: StringName = &"default"
@export var author: String = ""
@export var created_at: String = ""


func duplicate_arena() -> ArenaData:
	return ArenaData.from_dict(to_dict())


func is_in_bounds(cell: Vector3i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.z >= 0 \
		and cell.x < grid_size.x and cell.y < grid_size.y and cell.z < grid_size.z


# Serialization

func to_dict() -> Dictionary:
	var placement_dicts: Array = []
	for entry: PlacementEntry in placements:
		placement_dicts.append(entry.to_dict())
	var spawn_dicts: Array = []
	for spawn: EnemySpawnEntry in enemy_spawns:
		spawn_dicts.append(spawn.to_dict())
	return {
		"format_version": CURRENT_FORMAT_VERSION,
		"arena_name": arena_name,
		"grid_size": [grid_size.x, grid_size.y, grid_size.z],
		"placements": placement_dicts,
		"player_spawn": [player_spawn.x, player_spawn.y, player_spawn.z],
		"has_player_spawn": has_player_spawn,
		"theme_id": String(theme_id),
		"enemy_spawns": spawn_dicts,
		"author": author,
		"created_at": created_at,
	}


static func from_dict(data: Dictionary) -> ArenaData:
	var migrated: Dictionary = _migrate(data)
	var arena := ArenaData.new()
	arena.format_version = CURRENT_FORMAT_VERSION
	arena.arena_name = String(migrated.get("arena_name", ""))
	arena.grid_size = dict_to_cell(migrated.get("grid_size", []))
	arena.player_spawn = dict_to_cell(migrated.get("player_spawn", []))
	arena.has_player_spawn = bool(migrated.get("has_player_spawn", false))
	arena.theme_id = StringName(migrated.get("theme_id", "default"))
	arena.author = String(migrated.get("author", ""))
	arena.created_at = String(migrated.get("created_at", ""))
	var placements: Array[PlacementEntry] = []
	for entry_data: Variant in migrated.get("placements", []):
		placements.append(PlacementEntry.from_dict(entry_data as Dictionary))
	arena.placements = placements
	var spawns: Array[EnemySpawnEntry] = []
	for spawn_data: Variant in migrated.get("enemy_spawns", []):
		spawns.append(EnemySpawnEntry.from_dict(spawn_data as Dictionary))
	arena.enemy_spawns = spawns
	return arena


func to_json() -> String:
	return JSON.stringify(to_dict(), "\t")


static func from_json(text: String) -> ArenaData:
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return from_dict(parsed as Dictionary)
	push_error("ArenaData: could not parse arena JSON")
	return null


static func dict_to_cell(value: Variant) -> Vector3i:
	if value is Array and (value as Array).size() >= 3:
		var array: Array = value
		return Vector3i(int(array[0]), int(array[1]), int(array[2]))
	if value is Vector3i:
		return value
	return Vector3i.ZERO


# Private

## Carries a dictionary written by an older version up to the current shape.
## Each step is one version, so a v1 file walks every step to today.
static func _migrate(data: Dictionary) -> Dictionary:
	var result: Dictionary = data.duplicate(true)
	var version: int = int(result.get("format_version", 1))
	if version < 2:
		# v1 had no authorship fields and marked "no player spawn" with a null.
		result["author"] = result.get("author", "")
		result["created_at"] = result.get("created_at", "")
		if not result.has("has_player_spawn"):
			result["has_player_spawn"] = result.get("player_spawn", null) != null
		version = 2
	if version < 3:
		# v2 predates themes: everything made then was surrounded by nothing.
		result["theme_id"] = result.get("theme_id", "default")
		version = 3
	if version < 4:
		# v3 podia elegir entre tres tamanos. Las arenas guardadas entonces se
		# abren en el unico que hay ahora: la grilla solo puede crecer, asi que
		# nada queda fuera de bounds y lo que se construyo sigue donde estaba.
		result["grid_size"] = [FIXED_SIZE.x, FIXED_SIZE.y, FIXED_SIZE.z]
		version = 4
	result["format_version"] = version
	return result
