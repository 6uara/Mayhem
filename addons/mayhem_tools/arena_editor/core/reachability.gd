@tool
class_name Reachability
extends RefCounted
## Flood fill over the walkable grid. Deliberately not real navigation: this
## answers "is there a route at all", which is a level-design question, and it is
## cheap enough to run on every edit.


## Every cell reachable from `start`, as a set (cell -> true).
##
## `for_player` decides whether pads, zip lines and other player-only traversal
## count. "Can the player get there" and "can an enemy path there" are different
## questions and the validator asks both.
static func flood(graph: GridGraph, start: Vector3i, for_player: bool = false) -> Dictionary:
	var visited: Dictionary = {}
	if not graph.is_walkable(start):
		return visited
	var queue: Array[Vector3i] = [start]
	visited[start] = true
	while not queue.is_empty():
		var cell: Vector3i = queue.pop_front()
		for neighbor: Vector3i in graph.neighbors(cell, for_player):
			if visited.has(neighbor):
				continue
			visited[neighbor] = true
			queue.append(neighbor)
	return visited


## Every connected walkable region, largest first.
static func regions(graph: GridGraph, for_player: bool = false) -> Array:
	var seen: Dictionary = {}
	var found: Array = []
	for cell: Vector3i in graph.walkable_cells():
		if seen.has(cell):
			continue
		var region: Dictionary = flood(graph, cell, for_player)
		for member: Vector3i in region.keys():
			seen[member] = true
		found.append(region)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.size() > b.size())
	return found
