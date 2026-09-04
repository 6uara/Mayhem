@tool
class_name PlacementModel
extends RefCounted
## Every edit an arena can receive: place, rotate, erase, move the spawns.
##
## Knows nothing about docks, gizmos or the Godot editor. That is the whole point:
## the same object backs the plugin today and an in-game builder later, and the
## test suite drives it directly.

signal changed()

var arena: ArenaData
var catalog: PieceCatalog

## Single-level undo, as scoped in the handoff. Multi-level is out of v1.
var _undo_snapshot: Dictionary = {}
var _has_undo: bool = false


func _init(arena: ArenaData = null, catalog: PieceCatalog = null) -> void:
	self.arena = arena if arena != null else ArenaData.new()
	self.catalog = catalog


## Places `piece_id` with its origin at `cell`. Fails when the piece is unknown,
## the footprint leaves the grid, a cell it needs is taken in its own layer, or
## it needs a floor under it and there is none.
func place(piece_id: StringName, cell: Vector3i, rotation: int = 0) -> bool:
	return refusal_for(piece_id, cell, rotation) == &""


## Why `place` would refuse, as a code the UI can turn into a sentence, or empty
## when it would succeed. Placing goes through here so the answer to "why not"
## is never a second, drifting copy of the rules.
func refusal_for(piece_id: StringName, cell: Vector3i, rotation: int = 0,
		dry_run: bool = false) -> StringName:
	var piece: PieceDefinition = _piece(piece_id)
	if piece == null:
		return &"unknown_piece"
	var footprint: Array[Vector3i] = piece.get_footprint(rotation)
	for offset: Vector3i in footprint:
		var target: Vector3i = cell + offset
		if not arena.is_in_bounds(target):
			return &"out_of_bounds"
		if target.y < piece.min_level:
			return &"too_low"
		if is_occupied(target, piece.is_ground()):
			return &"cell_taken"
		if piece.is_ground():
			continue
		if piece.support == PieceDefinition.Support.FLOOR and not has_flat_ground(target):
			return &"needs_floor"
		if piece.support == PieceDefinition.Support.EMPTY 				and get_entry_at(target, true) != null:
			return &"needs_empty"
	if dry_run:
		return &""
	_snapshot()
	arena.placements.append(PlacementEntry.make(piece_id, cell, rotation))
	changed.emit()
	return &""


## True when `cell` holds a floor an interactable can sit on: walkable, and not a
## ramp - a pad or a crate on a slope reads as a bug, not as a design.
func has_flat_ground(cell: Vector3i) -> bool:
	var entry: PlacementEntry = get_entry_at(cell, true)
	if entry == null:
		return false
	var piece: PieceDefinition = _piece(entry.piece_id)
	if piece == null or piece.connects_levels:
		return false
	for offset: Vector3i in piece.get_walkable_cells(entry.rotation):
		if entry.cell + offset == cell:
			return true
	return false


## The entry covering `cell`. `ground` picks the layer: a floor tile and the wall
## standing on it share a cell, so "what is at this cell" needs to say which one.
## Passing nothing returns whichever layer is filled, body first - the piece a
## click is aiming at is the one you can see.
func get_entry_at(cell: Vector3i, ground: Variant = null) -> PlacementEntry:
	for entry: PlacementEntry in arena.placements:
		var piece: PieceDefinition = _piece(entry.piece_id)
		if piece == null:
			continue
		if ground != null and piece.is_ground() != bool(ground):
			continue
		for offset: Vector3i in piece.get_footprint(entry.rotation):
			if entry.cell + offset == cell:
				return entry
	return null


func is_occupied(cell: Vector3i, ground: Variant = null) -> bool:
	return get_entry_at(cell, ground) != null


## Erases the body piece at `cell` if there is one, and the ground piece
## otherwise: the same click that placed the wall takes the wall back first.
func erase_at(cell: Vector3i) -> bool:
	var entry: PlacementEntry = get_entry_at(cell, false)
	if entry == null:
		entry = get_entry_at(cell, true)
	if entry == null:
		return false
	_snapshot()
	arena.placements.erase(entry)
	changed.emit()
	return true


## Turns the piece covering `cell` by `turns` quarter turns. Reverts when the new
## footprint would collide, so a rotation never eats a neighbour.
func rotate_at(cell: Vector3i, turns: int = 1) -> bool:
	# Body first, like erasing: the piece you can see is the one you meant.
	var entry: PlacementEntry = get_entry_at(cell, false)
	if entry == null:
		entry = get_entry_at(cell, true)
	if entry == null:
		return false
	var piece: PieceDefinition = _piece(entry.piece_id)
	if piece == null:
		return false
	var new_rotation: int = posmod(entry.rotation + turns, 4)
	for offset: Vector3i in piece.get_footprint(new_rotation):
		var target: Vector3i = entry.cell + offset
		if not arena.is_in_bounds(target):
			return false
		var blocker: PlacementEntry = get_entry_at(target, piece.is_ground())
		if blocker != null and blocker != entry:
			return false
	_snapshot()
	entry.rotation = new_rotation
	changed.emit()
	return true


func set_player_spawn(cell: Vector3i) -> bool:
	if not arena.is_in_bounds(cell):
		return false
	_snapshot()
	arena.player_spawn = cell
	arena.has_player_spawn = true
	changed.emit()
	return true


func add_enemy_spawn(cell: Vector3i, archetype_id: StringName = &"") -> bool:
	if not arena.is_in_bounds(cell) or get_enemy_spawn_at(cell) != null:
		return false
	_snapshot()
	arena.enemy_spawns.append(EnemySpawnEntry.make(cell, archetype_id))
	changed.emit()
	return true


func get_enemy_spawn_at(cell: Vector3i) -> EnemySpawnEntry:
	for spawn: EnemySpawnEntry in arena.enemy_spawns:
		if spawn.cell == cell:
			return spawn
	return null


func remove_enemy_spawn(cell: Vector3i) -> bool:
	var spawn: EnemySpawnEntry = get_enemy_spawn_at(cell)
	if spawn == null:
		return false
	_snapshot()
	arena.enemy_spawns.erase(spawn)
	changed.emit()
	return true


func build_graph() -> GridGraph:
	return GridGraph.build(arena, catalog)


func can_undo() -> bool:
	return _has_undo


## Restores the state from before the last mutation. One level only.
func undo() -> bool:
	if not _has_undo:
		return false
	arena = ArenaData.from_dict(_undo_snapshot)
	_has_undo = false
	changed.emit()
	return true


# Private

func _piece(piece_id: StringName) -> PieceDefinition:
	if catalog == null:
		return null
	return catalog.get_piece(piece_id)


func _snapshot() -> void:
	_undo_snapshot = arena.to_dict()
	_has_undo = true
