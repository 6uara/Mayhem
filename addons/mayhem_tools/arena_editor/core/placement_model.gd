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
## Dentro de un trazo el snapshot se toma una sola vez, al principio. Sin esto,
## pintar veinte celdas arrastrando el mouse deja un undo que solo devuelve la
## ultima: cada edicion pisaba el snapshot de la anterior.
var _in_stroke: bool = false


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
	if piece.max_instances > 0 and count_of(piece_id) >= piece.max_instances:
		return &"piece_limit"
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


## Cuantas de `piece_id` hay puestas. Lo pregunta el tope de la pieza y lo
## pregunta la paleta para apagar el boton antes de que el click sea un rechazo.
func count_of(piece_id: StringName) -> int:
	var total: int = 0
	for entry: PlacementEntry in arena.placements:
		if entry.piece_id == piece_id:
			total += 1
	return total


## Lo puesto de cada pieza, en un solo recorrido. La paleta lo pide entera cada
## vez que la arena cambia, y llamar count_of() por boton seria recorrer las
## placements una vez por pieza del catalogo.
func counts_by_piece() -> Dictionary:
	var counts: Dictionary = {}
	for entry: PlacementEntry in arena.placements:
		counts[entry.piece_id] = int(counts.get(entry.piece_id, 0)) + 1
	return counts


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


## Todo lo que se edite hasta `end_stroke` cuenta como una sola accion para el
## undo. Anidar no tiene sentido y llamar dos veces seguidas es inofensivo.
func begin_stroke() -> void:
	if _in_stroke:
		return
	_snapshot()
	_in_stroke = true


func end_stroke() -> void:
	_in_stroke = false


## Levanta la pieza que cubre `from` y la baja en `to`, opcionalmente girada.
## Si el destino la rechaza no se pierde nada: la pieza vuelve donde estaba y se
## devuelve el codigo de rechazo, que es la misma frase que ya sabe decir la UI.
##
## `dry_run` responde "entraria" sin mover nada, que es lo que necesita el ghost
## para no mentir: preguntarle a `refusal_for` directamente daria "cell_taken"
## contra la propia pieza cada vez que el destino se solapa con el origen.
##
## Mover es sacar y poner, pero tiene que ser atomico: una pieza no puede quedar
## en el limbo porque el destino estaba ocupado, y menos todavia por su propia
## celda de origen, que es el caso mas comun de todos.
func move_to(from: Vector3i, to: Vector3i, rotation: Variant = null,
		dry_run: bool = false) -> StringName:
	var entry: PlacementEntry = get_entry_at(from, false)
	if entry == null:
		entry = get_entry_at(from, true)
	if entry == null:
		return &"nothing_there"
	var new_rotation: int = entry.rotation if rotation == null else posmod(int(rotation), 4)
	# El estado previo se guarda antes de tocar nada y se confirma solo si el
	# movimiento sale: un rechazo no tiene que gastar el unico undo que hay.
	# El ghost llama a esto en cada celda que pasa el mouse: serializar la arena
	# entera para un undo que no va a existir no es gratis.
	var before: Dictionary = {} if dry_run else arena.to_dict()
	var index: int = arena.placements.find(entry)
	arena.placements.remove_at(index)
	var refusal: StringName = refusal_for(entry.piece_id, to, new_rotation, true)
	if refusal != &"" or dry_run:
		arena.placements.insert(index, entry)
		return refusal
	entry.cell = to
	entry.rotation = new_rotation
	arena.placements.insert(index, entry)
	if not _in_stroke:
		_undo_snapshot = before
		_has_undo = true
	changed.emit()
	return &""


## Cubre de piso todas las celdas libres de `level` y devuelve cuantas piezas
## puso. Prueba primero las baldosas grandes: llenar 32x32 con la de una celda
## son mil entradas en el archivo y mil nodos en el preview, contra ciento pico
## si se usan las de 3x3 donde entran.
##
## Es codicioso y no optimo - el sobrante de un lado queda embaldosado con
## piezas chicas - y esta bien que lo sea: el resultado se ve igual y quien
## construye va a borrar la mitad de esto en el primer minuto.
##
## No pasa por `refusal_for` a proposito. Esa funcion pregunta por la ocupacion
## recorriendo todas las placements, una vez por celda del footprint, y con mil
## celdas contra cien piezas eso son millones de comparaciones en el unico
## momento en que el jugador esta esperando que abra el editor. Las unicas
## reglas que aplican a una baldosa de piso sobre un nivel vacio son el borde de
## la grilla y que la celda este libre, y las dos se contestan con este set.
func fill_floor(level: int = 0) -> int:
	if catalog == null:
		return 0
	var tiles: Array[PieceDefinition] = _floor_tiles()
	if tiles.is_empty():
		return 0
	var taken: Dictionary = {}
	for entry: PlacementEntry in arena.placements:
		var piece: PieceDefinition = _piece(entry.piece_id)
		if piece == null or not piece.is_ground():
			continue
		for offset: Vector3i in piece.get_footprint(entry.rotation):
			taken[entry.cell + offset] = true

	# El estado previo se guarda antes de embaldosar nada: un snapshot tomado
	# despues seria una foto del piso ya puesto, y Z no devolveria nada.
	var before: Dictionary = arena.to_dict()
	var placed: int = 0
	for x: int in arena.grid_size.x:
		for z: int in arena.grid_size.z:
			var cell := Vector3i(x, level, z)
			if taken.has(cell):
				continue
			for tile: PieceDefinition in tiles:
				var footprint: Array[Vector3i] = tile.get_footprint(0)
				if not _fits(footprint, cell, taken):
					continue
				for offset: Vector3i in footprint:
					taken[cell + offset] = true
				arena.placements.append(PlacementEntry.make(tile.id, cell, 0))
				placed += 1
				break
	if placed == 0:
		return 0
	if not _in_stroke:
		_undo_snapshot = before
		_has_undo = true
	changed.emit()
	return placed


## Las piezas de piso llano del catalogo, de la que mas cubre a la que menos.
## Las rampas quedan afuera: un piso base de rampas no es un piso.
func _floor_tiles() -> Array[PieceDefinition]:
	var tiles: Array[PieceDefinition] = []
	for piece: PieceDefinition in catalog.pieces:
		if piece == null or piece.connects_levels:
			continue
		if piece.category != PieceDefinition.Category.FLOOR:
			continue
		if piece.max_instances > 0:
			continue
		tiles.append(piece)
	tiles.sort_custom(func(a: PieceDefinition, b: PieceDefinition) -> bool:
		return a.footprint.size() > b.footprint.size())
	return tiles


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
	_in_stroke = false
	changed.emit()
	return true


# Private

func _fits(footprint: Array[Vector3i], cell: Vector3i, taken: Dictionary) -> bool:
	for offset: Vector3i in footprint:
		var target: Vector3i = cell + offset
		if not arena.is_in_bounds(target) or taken.has(target):
			return false
	return true


func _piece(piece_id: StringName) -> PieceDefinition:
	if catalog == null:
		return null
	return catalog.get_piece(piece_id)


func _snapshot() -> void:
	if _in_stroke:
		return
	_undo_snapshot = arena.to_dict()
	_has_undo = true
