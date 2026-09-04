@tool
class_name ArenaValidator
extends RefCounted
## Every rule an arena must pass before it can be saved or played.
##
## Errors block; warnings are advice. The list is ordered errors first so the
## panel reads top-down as "fix this, then consider this".


static func validate(arena: ArenaData, catalog: PieceCatalog,
		rules: ValidationRules = null) -> Array[ValidationIssue]:
	var issues: Array[ValidationIssue] = []
	if arena == null or catalog == null:
		return issues
	if rules == null:
		rules = ValidationRules.new()

	var graph: GridGraph = GridGraph.build(arena, catalog)
	issues.append_array(_check_placements(arena, catalog, graph))
	issues.append_array(_check_spawns(arena, graph, rules))
	issues.append_array(_check_connectivity(arena, graph, rules))
	issues.sort_custom(func(a: ValidationIssue, b: ValidationIssue) -> bool:
		return int(a.severity) < int(b.severity))
	return issues


static func errors(issues: Array[ValidationIssue]) -> Array[ValidationIssue]:
	var out: Array[ValidationIssue] = []
	for issue: ValidationIssue in issues:
		if issue.is_error():
			out.append(issue)
	return out


static func is_playable(arena: ArenaData, catalog: PieceCatalog,
		rules: ValidationRules = null) -> bool:
	return errors(validate(arena, catalog, rules)).is_empty()


# Private

static func _check_placements(arena: ArenaData, catalog: PieceCatalog,
		graph: GridGraph) -> Array[ValidationIssue]:
	var issues: Array[ValidationIssue] = []
	for layer: Dictionary in [graph.ground_occupancy, graph.body_occupancy]:
		for cell: Vector3i in layer.keys():
			if (layer[cell] as Array).size() > 1:
				issues.append(ValidationIssue.make(&"overlapping_pieces",
					ValidationIssue.Severity.ERROR,
					"Two pieces share the cell %s." % cell, cell))
	for entry: PlacementEntry in arena.placements:
		var piece: PieceDefinition = catalog.get_piece(entry.piece_id)
		if piece == null:
			issues.append(ValidationIssue.make(&"unknown_piece",
				ValidationIssue.Severity.ERROR,
				"No piece named '%s' in the catalog." % entry.piece_id, entry.cell))
			continue
		for offset: Vector3i in piece.get_footprint(entry.rotation):
			if not arena.is_in_bounds(entry.cell + offset):
				issues.append(ValidationIssue.make(&"piece_out_of_bounds",
					ValidationIssue.Severity.ERROR,
					"'%s' at %s sticks out of the grid." % [piece.display_name, entry.cell],
					entry.cell))
				break
	return issues


static func _check_spawns(arena: ArenaData, graph: GridGraph,
		rules: ValidationRules) -> Array[ValidationIssue]:
	var issues: Array[ValidationIssue] = []
	if not arena.has_player_spawn:
		issues.append(ValidationIssue.make(&"no_player_spawn",
			ValidationIssue.Severity.ERROR, "The arena has no player spawn."))
	elif not graph.is_walkable(arena.player_spawn):
		issues.append(ValidationIssue.make(&"spawn_not_walkable",
			ValidationIssue.Severity.ERROR,
			"The player spawn at %s is not on a walkable cell." % arena.player_spawn,
			arena.player_spawn))

	if arena.enemy_spawns.is_empty():
		issues.append(ValidationIssue.make(&"no_enemy_spawn",
			ValidationIssue.Severity.ERROR, "The arena has no enemy spawn."))

	var seen: Dictionary = {}
	for spawn: EnemySpawnEntry in arena.enemy_spawns:
		if not graph.is_walkable(spawn.cell):
			issues.append(ValidationIssue.make(&"spawn_not_walkable",
				ValidationIssue.Severity.ERROR,
				"The enemy spawn at %s is not on a walkable cell." % spawn.cell,
				spawn.cell))
		if seen.has(spawn.cell):
			issues.append(ValidationIssue.make(&"overlapping_spawns",
				ValidationIssue.Severity.WARNING,
				"Two enemy spawns share the cell %s." % spawn.cell, spawn.cell))
		seen[spawn.cell] = true
		if arena.has_player_spawn:
			var distance: int = absi(spawn.cell.x - arena.player_spawn.x) \
				+ absi(spawn.cell.z - arena.player_spawn.z)
			if distance < rules.min_spawn_distance:
				issues.append(ValidationIssue.make(&"spawns_too_close",
					ValidationIssue.Severity.WARNING,
					"The enemy spawn at %s is %d cells from the player." % [spawn.cell, distance],
					spawn.cell))
	return issues


static func _check_connectivity(arena: ArenaData, graph: GridGraph,
		rules: ValidationRules) -> Array[ValidationIssue]:
	var issues: Array[ValidationIssue] = []
	var walkable: Array[Vector3i] = graph.walkable_cells()
	if walkable.size() < rules.min_walkable_cells:
		issues.append(ValidationIssue.make(&"very_small_arena",
			ValidationIssue.Severity.WARNING,
			"Only %d walkable cells; arenas want at least %d."
				% [walkable.size(), rules.min_walkable_cells]))
	if not arena.has_player_spawn or not graph.is_walkable(arena.player_spawn):
		return issues  # Reachability is meaningless without a place to start.

	# Enemies have to be able to walk between their door and the player, so this
	# flood ignores pads and zip lines: an arena crossable only by bounce pad is
	# a broken arena for the horde even though the player can get around it.
	var reached: Dictionary = Reachability.flood(graph, arena.player_spawn, false)
	for spawn: EnemySpawnEntry in arena.enemy_spawns:
		if graph.is_walkable(spawn.cell) and not reached.has(spawn.cell):
			issues.append(ValidationIssue.make(&"unreachable_spawn",
				ValidationIssue.Severity.ERROR,
				"No route from the player spawn to the enemy spawn at %s." % spawn.cell,
				spawn.cell))
	# Cut-off regions are judged from the player's side, pads included: a ledge
	# only a bounce pad reaches is a design, not an island.
	var player_reached: Dictionary = Reachability.flood(graph, arena.player_spawn, true)
	for region: Dictionary in Reachability.regions(graph, true):
		var first: Vector3i = region.keys()[0]
		if player_reached.has(first):
			continue
		var holds_spawn: bool = false
		for spawn: EnemySpawnEntry in arena.enemy_spawns:
			if region.has(spawn.cell):
				holds_spawn = true
				break
		if not holds_spawn:
			issues.append(ValidationIssue.make(&"isolated_region",
				ValidationIssue.Severity.WARNING,
				"%d walkable cells around %s are cut off and hold no spawn."
					% [region.size(), first], first))
	return issues
