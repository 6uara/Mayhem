@tool
class_name EnemySpawnEntry
extends Resource
## One enemy spawn point on the grid.

@export var cell: Vector3i = Vector3i.ZERO
## Empty means "any archetype the wave asks for"; otherwise an `EnemyData.id`.
@export var archetype_id: StringName = &""


static func make(cell: Vector3i, archetype_id: StringName = &"") -> EnemySpawnEntry:
	var entry := EnemySpawnEntry.new()
	entry.cell = cell
	entry.archetype_id = archetype_id
	return entry


func to_dict() -> Dictionary:
	return {
		"cell": [cell.x, cell.y, cell.z],
		"archetype_id": String(archetype_id),
	}


static func from_dict(data: Dictionary) -> EnemySpawnEntry:
	return make(
		ArenaData.dict_to_cell(data.get("cell", [])),
		StringName(data.get("archetype_id", "")))
