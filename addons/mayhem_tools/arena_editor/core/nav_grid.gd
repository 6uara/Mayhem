@tool
class_name NavGrid
extends RefCounted
## A* over the same graph the validator uses (option A of the navigation
## decision, see docs/DECISION_navegacion_arenas.md).
##
## Nothing is baked: the arena's geometry is modular and known, so the path graph
## is the placement data itself. Preparation is free and the result is
## deterministic, which is what makes it testable.

var _graph: GridGraph
var _cell_size: Vector3
## Whether pads and other player-only links count as edges. Off by default: the
## common caller is "how would an enemy get there".
var for_player: bool = false


func _init(graph: GridGraph, cell_size: Vector3 = Vector3.ONE) -> void:
	_graph = graph
	_cell_size = cell_size


static func from_arena(arena: ArenaData, catalog: PieceCatalog) -> NavGrid:
	return NavGrid.new(GridGraph.build(arena, catalog), catalog.cell_size)


## Cells from `from` to `to` inclusive, or an empty array when there is no route.
func find_path(from: Vector3i, to: Vector3i) -> Array[Vector3i]:
	if not _graph.is_walkable(from) or not _graph.is_walkable(to):
		return []
	if from == to:
		return [from]
	var came_from: Dictionary = {}
	var cost: Dictionary = {from: 0.0}
	var open: Array = [[_heuristic(from, to), from]]
	while not open.is_empty():
		open.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var current: Vector3i = open.pop_front()[1]
		if current == to:
			return _reconstruct(came_from, current)
		for neighbor: Vector3i in _graph.neighbors(current, for_player):
			var next_cost: float = float(cost[current]) + _step_cost(current, neighbor)
			if cost.has(neighbor) and next_cost >= float(cost[neighbor]):
				continue
			cost[neighbor] = next_cost
			came_from[neighbor] = current
			open.append([next_cost + _heuristic(neighbor, to), neighbor])
	return []


## The same path in world space, with collinear waypoints dropped so agents move
## in straight runs instead of stepping cell by cell.
func find_world_path(from: Vector3i, to: Vector3i) -> PackedVector3Array:
	var cells: Array[Vector3i] = smooth(find_path(from, to))
	var out := PackedVector3Array()
	for cell: Vector3i in cells:
		out.append(Vector3(cell) * _cell_size)
	return out


## Drops waypoints that continue the previous direction.
static func smooth(cells: Array[Vector3i]) -> Array[Vector3i]:
	if cells.size() < 3:
		return cells
	var out: Array[Vector3i] = [cells[0]]
	for i: int in range(1, cells.size() - 1):
		if cells[i] - cells[i - 1] != cells[i + 1] - cells[i]:
			out.append(cells[i])
	out.append(cells[cells.size() - 1])
	return out


# Private

func _step_cost(from: Vector3i, to: Vector3i) -> float:
	return 1.0 if from.y == to.y else 1.5  # Climbing is worth avoiding, not banned.


func _heuristic(from: Vector3i, to: Vector3i) -> float:
	return float(absi(from.x - to.x) + absi(from.y - to.y) + absi(from.z - to.z))


func _reconstruct(came_from: Dictionary, current: Vector3i) -> Array[Vector3i]:
	var path: Array[Vector3i] = [current]
	while came_from.has(current):
		current = came_from[current]
		path.push_front(current)
	return path
