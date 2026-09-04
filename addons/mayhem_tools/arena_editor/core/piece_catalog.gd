@tool
class_name PieceCatalog
extends Resource
## The closed set of pieces an arena can be built from, plus the grid's scale.

## Metres per grid cell. The editor, the validator and the loader all read this;
## nothing converts cells to world space with a literal.
@export var cell_size: Vector3 = Vector3(4.0, 3.0, 4.0)
@export var pieces: Array[PieceDefinition] = []


func get_piece(id: StringName) -> PieceDefinition:
	for piece: PieceDefinition in pieces:
		if piece != null and piece.id == id:
			return piece
	return null


func has_piece(id: StringName) -> bool:
	return get_piece(id) != null


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for piece: PieceDefinition in pieces:
		if piece != null:
			out.append(piece.id)
	return out


## The cell's floor centre: pieces are built upward from here, and an agent on a
## walkable cell stands on whatever ground piece fills its bottom.
func cell_to_world(cell: Vector3i) -> Vector3:
	return Vector3(cell) * cell_size


func world_to_cell(world: Vector3) -> Vector3i:
	return Vector3i(
		int(round(world.x / cell_size.x)),
		int(floor(world.y / cell_size.y)),
		int(round(world.z / cell_size.z)))
