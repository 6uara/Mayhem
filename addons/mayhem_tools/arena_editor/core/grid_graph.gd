@tool
class_name GridGraph
extends RefCounted
## The walkable graph an arena's placed pieces add up to.
##
## Built once from `ArenaData` + `PieceCatalog` and then shared by reachability,
## validation and pathfinding, so the editor's "you can get there" and the game's
## "walk there" can never disagree.

const DIRECTIONS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

## cell -> true for every cell an agent can stand in.
var walkable: Dictionary = {}
## cell -> true for cells whose piece blocks travel.
var blocked: Dictionary = {}
## cell -> true for cells that connect two height levels (ramps).
var ramps: Dictionary = {}
## cell -> Array[int] of indices into `ArenaData.placements`, one dictionary per
## layer. Ground is what you stand on, body is what stands on it; a floor tile
## and the wall on top of it share a cell and are not an overlap.
var ground_occupancy: Dictionary = {}
var body_occupancy: Dictionary = {}
## walkable cell -> metres from the cell floor to the surface an agent stands on.
var surface_height: Dictionary = {}
## from cell -> Array of {"to": Vector3i, "players_only": bool} - the traversal a
## bounce pad, jump link or zip line adds on top of walking.
var links: Dictionary = {}


static func build(arena: ArenaData, catalog: PieceCatalog) -> GridGraph:
	var graph := GridGraph.new()
	if arena == null or catalog == null:
		return graph
	for index: int in arena.placements.size():
		var entry: PlacementEntry = arena.placements[index]
		var piece: PieceDefinition = catalog.get_piece(entry.piece_id)
		if piece == null:
			continue
		var layer: Dictionary = graph.ground_occupancy if piece.is_ground() 			else graph.body_occupancy
		for offset: Vector3i in piece.get_footprint(entry.rotation):
			var cell: Vector3i = entry.cell + offset
			var indices: Array = layer.get(cell, [])
			indices.append(index)
			layer[cell] = indices
			if piece.blocks_navigation:
				graph.blocked[cell] = true
		for offset: Vector3i in piece.get_walkable_cells(entry.rotation):
			var cell: Vector3i = entry.cell + offset
			graph.walkable[cell] = true
			graph.surface_height[cell] = piece.height_fraction() * catalog.cell_size.y
			if piece.connects_levels:
				graph.ramps[cell] = true
		for offset: Vector3i in piece.get_link_offsets(entry.rotation):
			graph.add_link(entry.cell, entry.cell + offset,
				piece.link_players_only, piece.link_is_one_way)
	return graph


func is_walkable(cell: Vector3i) -> bool:
	return walkable.has(cell) and not blocked.has(cell)


func add_link(from: Vector3i, to: Vector3i, players_only: bool, one_way: bool) -> void:
	_push_link(from, to, players_only)
	if not one_way:
		_push_link(to, from, players_only)


## Every link leaving `cell`. `for_player` is the whole point of the flag: the
## player rides pads and zip lines, enemies only get the links they can path.
func links_from(cell: Vector3i, for_player: bool) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for link: Dictionary in links.get(cell, []):
		if bool(link["players_only"]) and not for_player:
			continue
		if is_walkable(link["to"]):
			out.append(link["to"])
	return out


## Links an enemy can use too, as (from, to) pairs - what the loader turns into
## NavigationLink3D nodes so the navmesh knows about them.
func shared_links() -> Array[Array]:
	var out: Array[Array] = []
	for from: Vector3i in links.keys():
		for link: Dictionary in links[from]:
			if not bool(link["players_only"]) and is_walkable(link["to"]):
				out.append([from, link["to"]])
	return out


## Cells reachable from `cell` in one step, on foot plus whatever links apply.
## A level change costs a ramp on either side of it; flat neighbours are free.
func neighbors(cell: Vector3i, for_player: bool = false) -> Array[Vector3i]:
	var out: Array[Vector3i] = links_from(cell, for_player)
	for direction: Vector3i in DIRECTIONS:
		for dy: int in [0, 1, -1]:
			var candidate: Vector3i = cell + direction + Vector3i(0, dy, 0)
			if not is_walkable(candidate):
				continue
			if dy != 0 and not (ramps.has(cell) or ramps.has(candidate)):
				continue
			out.append(candidate)
			break
	return out


func _push_link(from: Vector3i, to: Vector3i, players_only: bool) -> void:
	var existing: Array = links.get(from, [])
	existing.append({"to": to, "players_only": players_only})
	links[from] = existing


func walkable_cells() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for cell: Vector3i in walkable.keys():
		if not blocked.has(cell):
			out.append(cell)
	return out


## Every layer's occupancy of `cell`, for the overlap check and the "what is
## here" query the editor makes on click.
func entries_at(cell: Vector3i) -> Array:
	var out: Array = []
	out.append_array(ground_occupancy.get(cell, []))
	out.append_array(body_occupancy.get(cell, []))
	return out


## Metres from the cell floor up to the surface of the ground piece in it, or 0
## when the cell has no ground. What a prop has to be lifted by to sit *on* the
## floor tile instead of halfway through it.
func surface_offset(cell: Vector3i) -> float:
	return float(surface_height.get(cell, 0.0))


## World position an agent standing on `cell` occupies, feet on the surface.
func standing_position(cell: Vector3i, cell_size: Vector3) -> Vector3:
	return Vector3(cell) * cell_size + Vector3(0.0, float(surface_height.get(cell, 0.0)), 0.0)


## The nearest walkable cell to `cell`, searching the column first. Used to snap
## spawns and to answer "which cell is under this click".
func snap_to_walkable(cell: Vector3i, max_drop: int = 4) -> Vector3i:
	for dy: int in range(0, max_drop + 1):
		var below := cell - Vector3i(0, dy, 0)
		if is_walkable(below):
			return below
	return cell
