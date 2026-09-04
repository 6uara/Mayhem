extends GutTest
## Every validation code from the spec: it fires on an arena built to break it,
## and stays quiet on a clean one.


func _catalog() -> PieceCatalog:
	var catalog := PieceCatalog.new()
	var floor_piece := PieceDefinition.new()
	floor_piece.id = &"floor"
	floor_piece.footprint = [Vector3i.ZERO]
	floor_piece.walkable_cells = [Vector3i.ZERO]
	var wall := PieceDefinition.new()
	wall.id = &"wall"
	wall.footprint = [Vector3i.ZERO]
	wall.blocks_navigation = true
	catalog.pieces = [floor_piece, wall]
	return catalog


func _rules() -> ValidationRules:
	var rules := ValidationRules.new()
	rules.min_walkable_cells = 4
	rules.min_spawn_distance = 2
	return rules


## A 6x1 strip of floor with the player at one end and an enemy at the other.
func _clean_model() -> PlacementModel:
	var arena := ArenaData.new()
	arena.grid_size = Vector3i(12, 4, 12)
	var model := PlacementModel.new(arena, _catalog())
	for x: int in 6:
		model.place(&"floor", Vector3i(x, 0, 0))
	model.set_player_spawn(Vector3i(0, 0, 0))
	model.add_enemy_spawn(Vector3i(5, 0, 0))
	return model


func _codes(model: PlacementModel) -> Array:
	var codes: Array = []
	for issue: ValidationIssue in ArenaValidator.validate(model.arena, model.catalog, _rules()):
		codes.append(issue.code)
	return codes


func test_a_clean_arena_reports_nothing() -> void:
	assert_eq(_codes(_clean_model()), [], "the reference arena must pass untouched")


func test_missing_player_spawn() -> void:
	var model: PlacementModel = _clean_model()
	model.arena.has_player_spawn = false
	assert_has(_codes(model), &"no_player_spawn")


func test_missing_enemy_spawn() -> void:
	var model: PlacementModel = _clean_model()
	model.arena.enemy_spawns.clear()
	assert_has(_codes(model), &"no_enemy_spawn")


func test_spawn_off_a_walkable_cell() -> void:
	var model: PlacementModel = _clean_model()
	model.set_player_spawn(Vector3i(9, 0, 9))
	assert_has(_codes(model), &"spawn_not_walkable")


func test_unreachable_spawn() -> void:
	var model: PlacementModel = _clean_model()
	model.place(&"floor", Vector3i(0, 0, 6))  # An island with no route to it.
	model.add_enemy_spawn(Vector3i(0, 0, 6))
	assert_has(_codes(model), &"unreachable_spawn")


func test_isolated_region_without_spawns_is_a_warning() -> void:
	var model: PlacementModel = _clean_model()
	model.place(&"floor", Vector3i(0, 0, 6))
	model.place(&"floor", Vector3i(1, 0, 6))
	assert_has(_codes(model), &"isolated_region")


func test_overlapping_pieces() -> void:
	var model: PlacementModel = _clean_model()
	# Force the overlap the model itself refuses to create.
	model.arena.placements.append(PlacementEntry.make(&"floor", Vector3i(0, 0, 0)))
	assert_has(_codes(model), &"overlapping_pieces")


func test_piece_out_of_bounds() -> void:
	var model: PlacementModel = _clean_model()
	model.arena.placements.append(PlacementEntry.make(&"floor", Vector3i(50, 0, 0)))
	assert_has(_codes(model), &"piece_out_of_bounds")


func test_very_small_arena_is_a_warning() -> void:
	var arena := ArenaData.new()
	arena.grid_size = Vector3i(8, 4, 8)
	var model := PlacementModel.new(arena, _catalog())
	model.place(&"floor", Vector3i.ZERO)
	model.set_player_spawn(Vector3i.ZERO)
	model.add_enemy_spawn(Vector3i.ZERO)
	assert_has(_codes(model), &"very_small_arena")


func test_spawns_too_close_is_a_warning() -> void:
	var model: PlacementModel = _clean_model()
	model.add_enemy_spawn(Vector3i(1, 0, 0))
	assert_has(_codes(model), &"spawns_too_close")


func test_errors_block_playability_and_warnings_do_not() -> void:
	var model: PlacementModel = _clean_model()
	model.add_enemy_spawn(Vector3i(1, 0, 0))  # Warning only.
	assert_true(ArenaValidator.is_playable(model.arena, model.catalog, _rules()))
	model.arena.has_player_spawn = false
	assert_false(ArenaValidator.is_playable(model.arena, model.catalog, _rules()))


func test_a_ledge_only_a_pad_reaches_is_not_an_isolated_region() -> void:
	var catalog: PieceCatalog = _catalog()
	var pad := PieceDefinition.new()
	pad.id = &"pad"
	pad.category = PieceDefinition.Category.PROP
	pad.footprint = [Vector3i.ZERO]
	pad.link_offsets = [Vector3i(0, 1, 0)]
	catalog.pieces.append(pad)

	var arena := ArenaData.new()
	arena.grid_size = Vector3i(12, 4, 12)
	var model := PlacementModel.new(arena, catalog)
	for x: int in 6:
		model.place(&"floor", Vector3i(x, 0, 0))
	model.place(&"floor", Vector3i(0, 1, 0))  # The ledge over the strip.
	model.place(&"pad", Vector3i(0, 0, 0))
	model.set_player_spawn(Vector3i(0, 0, 0))
	model.add_enemy_spawn(Vector3i(5, 0, 0))

	var codes: Array = []
	for issue: ValidationIssue in ArenaValidator.validate(arena, catalog, _rules()):
		codes.append(issue.code)
	assert_does_not_have(codes, &"isolated_region",
		"the pad is how the player gets up there, so the ledge is a design")
	assert_does_not_have(codes, &"unreachable_spawn", "the enemy spawn is on the strip")
