@tool
class_name ArenaPreview
extends Node3D
## What the designer sees while editing: the placed pieces, the grid of the
## working level, the spawn markers and the ghost under the cursor.
##
## Rebuilt wholesale on every change. An arena is a few hundred boxes, so the
## simple thing is also the fast enough thing.

var model: PlacementModel
var level: int = 0

var _geometry: Node3D
var _overlay: Node3D
var _ghost: Node3D
var _ghost_piece_id: StringName = &""
var _ghost_rotation: int = -1
var _ghost_valid: bool = true


func _ready() -> void:
	_geometry = _make_child("Geometry")
	_overlay = _make_child("Overlay")


func rebuild() -> void:
	if model == null or model.catalog == null or _geometry == null:
		return
	_clear(_geometry)
	_clear(_overlay)
	var catalog: PieceCatalog = model.catalog
	var graph: GridGraph = model.build_graph()
	for entry: PlacementEntry in model.arena.placements:
		var piece: PieceDefinition = catalog.get_piece(entry.piece_id)
		if piece == null:
			continue
		var node: Node3D = PieceMeshBuilder.build(piece, catalog, false)
		if node == null:
			continue
		# Same lift as the loader: what you place is what you get.
		node.position = catalog.cell_to_world(entry.cell) + Vector3(
			0.0, 0.0 if piece.is_ground() else graph.surface_offset(entry.cell), 0.0)
		node.rotation.y = deg_to_rad(-90.0 * entry.rotation)
		_geometry.add_child(node)

	_overlay.add_child(ArenaGizmos.build_grid(model.arena.grid_size, catalog.cell_size, level))
	if model.arena.has_player_spawn:
		_add_marker(model.arena.player_spawn, ArenaGizmos.PLAYER_SPAWN_COLOR)
	for spawn: EnemySpawnEntry in model.arena.enemy_spawns:
		_add_marker(spawn.cell, ArenaGizmos.ENEMY_SPAWN_COLOR)


## Moves the ghost to `cell`, rebuilding it only when the piece or rotation changed.
func show_ghost(piece_id: StringName, cell: Vector3i, rotation: int, valid: bool) -> void:
	if model == null or model.catalog == null:
		return
	var piece: PieceDefinition = model.catalog.get_piece(piece_id)
	if piece == null:
		hide_ghost()
		return
	# Validity is part of what the ghost is, not just how it is tinted: rebuilding
	# on a change is what makes red actually mean "this click will not work".
	if _ghost == null or _ghost_piece_id != piece_id or _ghost_rotation != rotation 			or _ghost_valid != valid:
		hide_ghost()
		_ghost = PieceMeshBuilder.build_preview(piece, model.catalog,
			ArenaGizmos.GHOST_VALID if valid else ArenaGizmos.GHOST_INVALID)
		_ghost_piece_id = piece_id
		_ghost_rotation = rotation
		_ghost_valid = valid
		add_child(_ghost)
	var lift: float = 0.0 if piece.is_ground() else model.build_graph().surface_offset(cell)
	_ghost.position = model.catalog.cell_to_world(cell) + Vector3(0.0, lift, 0.0)
	_ghost.rotation.y = deg_to_rad(-90.0 * rotation)


func hide_ghost() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
		_ghost_piece_id = &""
		_ghost_rotation = -1


# Private

func _add_marker(cell: Vector3i, color: Color) -> void:
	var marker: MeshInstance3D = ArenaGizmos.build_spawn_marker(color, model.catalog.cell_size)
	marker.position = model.catalog.cell_to_world(cell)
	_overlay.add_child(marker)


func _make_child(child_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = child_name
	add_child(node)
	return node


func _clear(parent: Node3D) -> void:
	for child: Node in parent.get_children():
		child.queue_free()
