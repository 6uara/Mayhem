@tool
class_name PlacementEntry
extends Resource
## One piece placed on the grid.

@export var piece_id: StringName = &""
@export var cell: Vector3i = Vector3i.ZERO
## Quarter turns around Y, 0-3.
@export var rotation: int = 0


static func make(piece_id: StringName, cell: Vector3i, rotation: int = 0) -> PlacementEntry:
	var entry := PlacementEntry.new()
	entry.piece_id = piece_id
	entry.cell = cell
	entry.rotation = posmod(rotation, 4)
	return entry


func to_dict() -> Dictionary:
	return {
		"piece_id": String(piece_id),
		"cell": [cell.x, cell.y, cell.z],
		"rotation": rotation,
	}


static func from_dict(data: Dictionary) -> PlacementEntry:
	return make(
		StringName(data.get("piece_id", "")),
		ArenaData.dict_to_cell(data.get("cell", [])),
		int(data.get("rotation", 0)))
