extends GutTest
## The grid graph the validator and the pathfinder share: flood fill, level
## changes through ramps, and A* over the result.


func _catalog() -> PieceCatalog:
	var catalog := PieceCatalog.new()
	catalog.cell_size = Vector3(4.0, 3.0, 4.0)
	var floor_piece := PieceDefinition.new()
	floor_piece.id = &"floor"
	floor_piece.footprint = [Vector3i.ZERO]
	floor_piece.walkable_cells = [Vector3i.ZERO]
	var ramp := PieceDefinition.new()
	ramp.id = &"ramp"
	ramp.footprint = [Vector3i.ZERO]
	ramp.walkable_cells = [Vector3i.ZERO]
	ramp.connects_levels = true
	catalog.pieces = [floor_piece, ramp]
	return catalog


func _model() -> PlacementModel:
	var arena := ArenaData.new()
	arena.grid_size = Vector3i(16, 4, 16)
	return PlacementModel.new(arena, _catalog())


func test_flood_reaches_a_connected_strip() -> void:
	var model: PlacementModel = _model()
	for x: int in 5:
		model.place(&"floor", Vector3i(x, 0, 0))
	var reached: Dictionary = Reachability.flood(model.build_graph(), Vector3i.ZERO)
	assert_eq(reached.size(), 5)


func test_flood_stops_at_a_gap() -> void:
	var model: PlacementModel = _model()
	model.place(&"floor", Vector3i(0, 0, 0))
	model.place(&"floor", Vector3i(2, 0, 0))
	var reached: Dictionary = Reachability.flood(model.build_graph(), Vector3i.ZERO)
	assert_eq(reached.size(), 1)


func test_two_regions_are_reported_separately() -> void:
	var model: PlacementModel = _model()
	model.place(&"floor", Vector3i(0, 0, 0))
	model.place(&"floor", Vector3i(1, 0, 0))
	model.place(&"floor", Vector3i(5, 0, 5))
	var regions: Array = Reachability.regions(model.build_graph())
	assert_eq(regions.size(), 2)
	assert_eq((regions[0] as Dictionary).size(), 2, "the largest region comes first")


func test_a_level_change_needs_a_ramp() -> void:
	var model: PlacementModel = _model()
	model.place(&"floor", Vector3i(0, 0, 0))
	model.place(&"floor", Vector3i(1, 1, 0))
	assert_eq(Reachability.flood(model.build_graph(), Vector3i.ZERO).size(), 1,
		"a bare step up is not walkable")

	model.erase_at(Vector3i(1, 1, 0))
	model.place(&"ramp", Vector3i(1, 1, 0))
	assert_eq(Reachability.flood(model.build_graph(), Vector3i.ZERO).size(), 2,
		"the ramp connects the two levels")


func test_a_star_finds_a_route_around_a_hole() -> void:
	var model: PlacementModel = _model()
	for x: int in 3:
		for z: int in 3:
			if x == 1 and z == 1:
				continue  # The hole in the middle.
			model.place(&"floor", Vector3i(x, 0, z))
	var nav: NavGrid = NavGrid.from_arena(model.arena, model.catalog)
	var path: Array[Vector3i] = nav.find_path(Vector3i(0, 0, 1), Vector3i(2, 0, 1))
	assert_gt(path.size(), 3, "the direct line is blocked, so the route goes around")
	assert_eq(path[0], Vector3i(0, 0, 1))
	assert_eq(path[path.size() - 1], Vector3i(2, 0, 1))
	assert_does_not_have(path, Vector3i(1, 0, 1))


func test_no_path_between_disconnected_cells() -> void:
	var model: PlacementModel = _model()
	model.place(&"floor", Vector3i(0, 0, 0))
	model.place(&"floor", Vector3i(5, 0, 5))
	var nav: NavGrid = NavGrid.from_arena(model.arena, model.catalog)
	assert_eq(nav.find_path(Vector3i(0, 0, 0), Vector3i(5, 0, 5)), [])


func test_smoothing_drops_collinear_waypoints() -> void:
	var straight: Array[Vector3i] = [
		Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(3, 0, 0),
	]
	assert_eq(NavGrid.smooth(straight), [Vector3i(0, 0, 0), Vector3i(3, 0, 0)])


func _pad_catalog() -> PieceCatalog:
	var catalog: PieceCatalog = _catalog()
	var pad := PieceDefinition.new()
	pad.id = &"pad"
	pad.category = PieceDefinition.Category.PROP
	pad.footprint = [Vector3i.ZERO]
	pad.link_offsets = [Vector3i(0, 1, 0)]
	pad.link_players_only = true
	pad.link_is_one_way = true
	var jump := PieceDefinition.new()
	jump.id = &"jump"
	jump.category = PieceDefinition.Category.PROP
	jump.footprint = [Vector3i.ZERO]
	jump.link_offsets = [Vector3i(0, 1, 2)]
	jump.link_players_only = false
	jump.link_is_one_way = false
	catalog.pieces.append(pad)
	catalog.pieces.append(jump)
	return catalog


## Two floors, one level apart and far enough that nothing walks between them.
func _split_model(link_id: StringName, link_cell: Vector3i, top: Vector3i) -> PlacementModel:
	var arena := ArenaData.new()
	arena.grid_size = Vector3i(16, 4, 16)
	var model := PlacementModel.new(arena, _pad_catalog())
	model.place(&"floor", Vector3i(0, 0, 0))
	model.place(&"floor", top)
	model.place(link_id, link_cell)
	return model


func test_a_pad_link_carries_the_player_up() -> void:
	var model: PlacementModel = _split_model(&"pad", Vector3i(0, 0, 0), Vector3i(0, 1, 0))
	var graph: GridGraph = model.build_graph()
	assert_eq(Reachability.flood(graph, Vector3i.ZERO, true).size(), 2,
		"the player rides the pad up")
	assert_eq(Reachability.flood(graph, Vector3i.ZERO, false).size(), 1,
		"the horde cannot use a pad, so for them the ledge is unreachable")


func test_a_pad_link_is_one_way() -> void:
	var model: PlacementModel = _split_model(&"pad", Vector3i(0, 0, 0), Vector3i(0, 1, 0))
	var graph: GridGraph = model.build_graph()
	assert_eq(Reachability.flood(graph, Vector3i(0, 1, 0), true).size(), 1,
		"a pad throws you up, it does not bring you down")


func test_a_jump_link_works_for_everyone_and_both_ways() -> void:
	var model: PlacementModel = _split_model(&"jump", Vector3i(0, 0, 0), Vector3i(0, 1, 2))
	var graph: GridGraph = model.build_graph()
	assert_eq(Reachability.flood(graph, Vector3i.ZERO, false).size(), 2,
		"the horde gets jump links")
	assert_eq(Reachability.flood(graph, Vector3i(0, 1, 2), false).size(), 2,
		"and they are bidirectional")


func test_only_shared_links_are_published_to_the_navmesh() -> void:
	var model: PlacementModel = _split_model(&"pad", Vector3i(0, 0, 0), Vector3i(0, 1, 0))
	assert_eq(model.build_graph().shared_links().size(), 0,
		"a pad the enemies cannot ride must not become a navigation link")
	var jumps: PlacementModel = _split_model(&"jump", Vector3i(0, 0, 0), Vector3i(0, 1, 2))
	assert_eq(jumps.build_graph().shared_links().size(), 2, "one per direction")


func test_a_link_rotates_with_its_piece() -> void:
	var catalog: PieceCatalog = _pad_catalog()
	var piece: PieceDefinition = catalog.get_piece(&"jump")
	assert_eq(piece.get_link_offsets(0), [Vector3i(0, 1, 2)])
	assert_eq(piece.get_link_offsets(1), [Vector3i(-2, 1, 0)], "a quarter turn around Y")
	assert_eq(piece.get_link_offsets(4), piece.get_link_offsets(0))


func test_a_star_will_not_route_an_enemy_over_a_pad() -> void:
	var model: PlacementModel = _split_model(&"pad", Vector3i(0, 0, 0), Vector3i(0, 1, 0))
	var nav := NavGrid.new(model.build_graph(), model.catalog.cell_size)
	assert_eq(nav.find_path(Vector3i.ZERO, Vector3i(0, 1, 0)), [], "no enemy route")
	nav.for_player = true
	assert_eq(nav.find_path(Vector3i.ZERO, Vector3i(0, 1, 0)).size(), 2, "the player has one")
