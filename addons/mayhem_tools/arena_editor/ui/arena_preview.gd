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
var _highlight: Node3D
var _highlight_key: Array = []


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
		node.position = ArenaLoader.piece_position(piece, entry, catalog, graph)
		node.rotation.y = deg_to_rad(-90.0 * entry.rotation)
		if piece.moves():
			# Quieta en su punta de partida: una plataforma andando en el editor
			# no se puede apuntar, y el recorrido ya lo dice la linea.
			node.process_mode = Node.PROCESS_MODE_DISABLED
			_overlay.add_child(_travel_path(piece, entry.rotation, node.position))
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
		if piece.moves():
			# El recorrido va con el ghost, en su espacio y sin girar: el ghost ya
			# esta girado, y asi la linea gira con R sin rearmarse. Rojo si no
			# entra, porque lo que suele no entrar es justamente el camino.
			_ghost.add_child(ArenaGizmos.build_travel_path(
				Vector3(0.0, _ghost_top(piece), 0.0),
				Vector3(piece.travel_cells) * model.catalog.cell_size
					+ Vector3(0.0, _ghost_top(piece), 0.0),
				_footprint_size(piece),
				ArenaGizmos.TRAVEL_PATH_COLOR if valid else ArenaGizmos.GHOST_INVALID))
		_ghost_piece_id = piece_id
		_ghost_rotation = rotation
		_ghost_valid = valid
		add_child(_ghost)
	var lift: float = 0.0 if piece.is_ground() else model.build_graph().surface_offset(cell)
	# El ghost es la caja gris, armada desde el piso de la celda; la escena real
	# cuelga centrada a su `hang_height`. Se baja media caja para que coincidan.
	if piece.hang_height > 0.0:
		lift += piece.hang_height - _greybox_height(piece) * 0.5
	_ghost.position = model.catalog.cell_to_world(cell) + Vector3(0.0, lift, 0.0)
	_ghost.rotation.y = deg_to_rad(-90.0 * rotation)


## Marca la pieza que cubre `cell` - lo que un click de borrar o de mover se va
## a llevar. Se dibuja el footprint entero y no solo la celda apuntada: una
## rampa de dos celdas se borra completa, y el resaltado tiene que decirlo.
func show_piece_highlight(cell: Vector3i, color: Color) -> void:
	if model == null or model.catalog == null:
		hide_highlight()
		return
	var entry: PlacementEntry = model.get_entry_at(cell, false)
	if entry == null:
		entry = model.get_entry_at(cell, true)
	if entry == null:
		hide_highlight()
		return
	var piece: PieceDefinition = model.catalog.get_piece(entry.piece_id)
	if piece == null:
		hide_highlight()
		return
	var key: Array = [entry.cell, entry.rotation, entry.piece_id, color]
	if _highlight != null and _highlight_key == key:
		return
	hide_highlight()
	_highlight = Node3D.new()
	_highlight_key = key
	for offset: Vector3i in piece.get_footprint(entry.rotation):
		var outline: MeshInstance3D = ArenaGizmos.build_cell_outline(
			color, model.catalog.cell_size)
		outline.position = model.catalog.cell_to_world(entry.cell + offset)
		_highlight.add_child(outline)
	add_child(_highlight)


func hide_highlight() -> void:
	if _highlight != null:
		_highlight.queue_free()
		_highlight = null
		_highlight_key = []


func hide_ghost() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
		_ghost_piece_id = &""
		_ghost_rotation = -1


# Private

## El recorrido de una pieza movil ya puesta, en el espacio del preview.
## `origin` es donde quedo el origen de la escena, que cuelga centrada.
func _travel_path(piece: PieceDefinition, rotation: int, origin: Vector3) -> Node3D:
	var top := Vector3(0.0, _greybox_height(piece) * 0.5, 0.0)
	var from: Vector3 = origin + top
	var to: Vector3 = from + Vector3(piece.get_travel(rotation)) * model.catalog.cell_size
	var size: Vector2 = _footprint_size(piece)
	if posmod(rotation, 2) == 1:
		size = Vector2(size.y, size.x)
	return ArenaGizmos.build_travel_path(from, to, size, ArenaGizmos.TRAVEL_PATH_COLOR)


## Alto de la caja gris de la pieza, que es tambien el grosor de la losa real.
func _greybox_height(piece: PieceDefinition) -> float:
	return model.catalog.cell_size.y * piece.greybox_extents.y


## La cara de arriba del ghost, medida desde su propio origen (su base).
func _ghost_top(piece: PieceDefinition) -> float:
	return _greybox_height(piece)


func _footprint_size(piece: PieceDefinition) -> Vector2:
	return Vector2(model.catalog.cell_size.x * piece.greybox_extents.x,
		model.catalog.cell_size.z * piece.greybox_extents.z)


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
