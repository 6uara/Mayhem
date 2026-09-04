extends GutTest
## Placement, rotation and erasing on the grid. The model is UI-free by design,
## which is what lets these run headless.


func _catalog() -> PieceCatalog:
	var catalog := PieceCatalog.new()
	catalog.cell_size = Vector3(4.0, 3.0, 4.0)

	var floor_piece := PieceDefinition.new()
	floor_piece.id = &"floor"
	floor_piece.footprint = [Vector3i.ZERO]
	floor_piece.walkable_cells = [Vector3i.ZERO]

	var long_piece := PieceDefinition.new()
	long_piece.id = &"long"
	long_piece.footprint = [Vector3i.ZERO, Vector3i(1, 0, 0)]
	long_piece.walkable_cells = [Vector3i.ZERO, Vector3i(1, 0, 0)]

	catalog.pieces = [floor_piece, long_piece]
	return catalog


func _model() -> PlacementModel:
	var arena := ArenaData.new()
	arena.grid_size = Vector3i(8, 4, 8)
	return PlacementModel.new(arena, _catalog())


func test_place_adds_an_entry() -> void:
	var model: PlacementModel = _model()
	assert_true(model.place(&"floor", Vector3i(2, 0, 2)))
	assert_eq(model.arena.placements.size(), 1)
	assert_eq(model.arena.placements[0].cell, Vector3i(2, 0, 2))


func test_place_on_an_occupied_cell_fails() -> void:
	var model: PlacementModel = _model()
	model.place(&"floor", Vector3i(2, 0, 2))
	assert_false(model.place(&"floor", Vector3i(2, 0, 2)))
	assert_eq(model.arena.placements.size(), 1, "the failed placement left nothing behind")


func test_place_out_of_bounds_fails() -> void:
	var model: PlacementModel = _model()
	assert_false(model.place(&"floor", Vector3i(-1, 0, 0)))
	assert_false(model.place(&"long", Vector3i(7, 0, 0)), "the second cell is off the grid")


func test_unknown_piece_is_refused() -> void:
	var model: PlacementModel = _model()
	assert_false(model.place(&"nonexistent", Vector3i.ZERO))


func test_four_rotations_return_the_original_footprint() -> void:
	var piece: PieceDefinition = _catalog().get_piece(&"long")
	assert_eq(piece.get_footprint(4), piece.get_footprint(0))
	assert_ne(piece.get_footprint(1), piece.get_footprint(0))


func test_rotation_moves_the_second_cell() -> void:
	var model: PlacementModel = _model()
	model.place(&"long", Vector3i(2, 0, 2))
	assert_true(model.rotate_at(Vector3i(3, 0, 2)), "the piece covers both cells")
	assert_not_null(model.get_entry_at(Vector3i(2, 0, 3)), "rotated onto +z")
	assert_null(model.get_entry_at(Vector3i(3, 0, 2)))


func test_rotation_is_refused_when_it_would_collide() -> void:
	var model: PlacementModel = _model()
	model.place(&"long", Vector3i(2, 0, 2))
	model.place(&"floor", Vector3i(2, 0, 3))
	assert_false(model.rotate_at(Vector3i(2, 0, 2)))
	assert_not_null(model.get_entry_at(Vector3i(3, 0, 2)), "the piece kept its old footprint")


func test_erase_removes_the_piece_from_any_of_its_cells() -> void:
	var model: PlacementModel = _model()
	model.place(&"long", Vector3i(2, 0, 2))
	assert_true(model.erase_at(Vector3i(3, 0, 2)))
	assert_eq(model.arena.placements.size(), 0)


func test_undo_restores_the_previous_state() -> void:
	var model: PlacementModel = _model()
	model.place(&"floor", Vector3i(1, 0, 1))
	model.place(&"floor", Vector3i(2, 0, 2))
	assert_true(model.undo())
	assert_eq(model.arena.placements.size(), 1)
	assert_false(model.undo(), "undo is one level deep, as scoped")


func test_enemy_spawns_toggle_by_cell() -> void:
	var model: PlacementModel = _model()
	assert_true(model.add_enemy_spawn(Vector3i(1, 0, 1)))
	assert_false(model.add_enemy_spawn(Vector3i(1, 0, 1)), "one spawn per cell")
	assert_true(model.remove_enemy_spawn(Vector3i(1, 0, 1)))


func test_a_body_piece_shares_the_cell_with_the_floor_under_it() -> void:
	var catalog: PieceCatalog = _catalog()
	var wall := PieceDefinition.new()
	wall.id = &"wall"
	wall.category = PieceDefinition.Category.WALL
	wall.footprint = [Vector3i.ZERO]
	wall.blocks_navigation = true
	catalog.pieces.append(wall)
	var arena := ArenaData.new()
	arena.grid_size = Vector3i(8, 4, 8)
	var model := PlacementModel.new(arena, catalog)

	assert_true(model.place(&"floor", Vector3i(1, 0, 1)))
	assert_true(model.place(&"wall", Vector3i(1, 0, 1)), "a wall stands on the floor tile")
	assert_false(model.place(&"wall", Vector3i(1, 0, 1)), "but only one wall per cell")
	assert_eq(ArenaValidator.errors(ArenaValidator.validate(arena, catalog)).size(), 2,
		"floor plus wall is not an overlap - only the missing spawns are errors")


func test_erasing_takes_the_body_piece_before_the_floor() -> void:
	var catalog: PieceCatalog = _catalog()
	var wall := PieceDefinition.new()
	wall.id = &"wall"
	wall.category = PieceDefinition.Category.WALL
	wall.footprint = [Vector3i.ZERO]
	catalog.pieces.append(wall)
	var arena := ArenaData.new()
	arena.grid_size = Vector3i(8, 4, 8)
	var model := PlacementModel.new(arena, catalog)
	model.place(&"floor", Vector3i(1, 0, 1))
	model.place(&"wall", Vector3i(1, 0, 1))

	assert_true(model.erase_at(Vector3i(1, 0, 1)))
	assert_null(model.get_entry_at(Vector3i(1, 0, 1), false), "the wall went first")
	assert_not_null(model.get_entry_at(Vector3i(1, 0, 1), true), "the floor stayed")


func _interactable_catalog() -> PieceCatalog:
	var catalog: PieceCatalog = _catalog()
	var ramp := PieceDefinition.new()
	ramp.id = &"ramp"
	ramp.category = PieceDefinition.Category.RAMP
	ramp.footprint = [Vector3i.ZERO]
	ramp.walkable_cells = [Vector3i.ZERO]
	ramp.connects_levels = true
	var pad := PieceDefinition.new()
	pad.id = &"pad"
	pad.category = PieceDefinition.Category.PROP
	pad.footprint = [Vector3i.ZERO]
	pad.support = PieceDefinition.Support.FLOOR
	var anchor := PieceDefinition.new()
	anchor.id = &"anchor"
	anchor.category = PieceDefinition.Category.PROP
	anchor.footprint = [Vector3i.ZERO]
	anchor.support = PieceDefinition.Support.EMPTY
	anchor.min_level = 2
	var wall := PieceDefinition.new()
	wall.id = &"wall"
	wall.category = PieceDefinition.Category.WALL
	wall.footprint = [Vector3i.ZERO]
	catalog.pieces.append(ramp)
	catalog.pieces.append(pad)
	catalog.pieces.append(anchor)
	catalog.pieces.append(wall)
	return catalog


func _interactable_model() -> PlacementModel:
	var arena := ArenaData.new()
	arena.grid_size = Vector3i(8, 6, 8)
	return PlacementModel.new(arena, _interactable_catalog())


func test_an_interactable_goes_on_a_floor_tile() -> void:
	var model: PlacementModel = _interactable_model()
	model.place(&"floor", Vector3i(2, 0, 2))
	assert_true(model.place(&"pad", Vector3i(2, 0, 2)),
		"a bounce pad on a floor tile is the normal case, not a collision")


func test_an_interactable_needs_something_under_it() -> void:
	var model: PlacementModel = _interactable_model()
	assert_eq(model.refusal_for(&"pad", Vector3i(2, 0, 2)), &"needs_floor",
		"nothing to stand on")


func test_an_interactable_is_refused_on_a_ramp() -> void:
	var model: PlacementModel = _interactable_model()
	model.place(&"ramp", Vector3i(2, 0, 2))
	assert_eq(model.refusal_for(&"pad", Vector3i(2, 0, 2)), &"needs_floor",
		"a pad on a slope reads as a bug")


func test_two_interactables_still_cannot_share_a_cell() -> void:
	var model: PlacementModel = _interactable_model()
	model.place(&"floor", Vector3i(2, 0, 2))
	model.place(&"pad", Vector3i(2, 0, 2))
	assert_eq(model.refusal_for(&"pad", Vector3i(2, 0, 2)), &"cell_taken")


func test_structure_stacks_without_a_floor_under_it() -> void:
	var model: PlacementModel = _interactable_model()
	model.place(&"floor", Vector3i(2, 0, 2))
	assert_true(model.place(&"wall", Vector3i(2, 0, 2)))
	assert_true(model.place(&"wall", Vector3i(2, 1, 2)),
		"walls build height; only interactables need a floor of their own")


func test_a_dry_run_answers_without_placing_anything() -> void:
	var model: PlacementModel = _interactable_model()
	model.place(&"floor", Vector3i(2, 0, 2))
	assert_eq(model.refusal_for(&"pad", Vector3i(2, 0, 2), 0, true), &"")
	assert_eq(model.arena.placements.size(), 1, "the ghost must not build")


func test_rotating_takes_the_body_piece_over_the_floor() -> void:
	var model: PlacementModel = _interactable_model()
	model.place(&"floor", Vector3i(2, 0, 2))
	model.place(&"pad", Vector3i(2, 0, 2))
	model.rotate_at(Vector3i(2, 0, 2))
	assert_eq(model.get_entry_at(Vector3i(2, 0, 2), false).rotation, 1, "the pad turned")
	assert_eq(model.get_entry_at(Vector3i(2, 0, 2), true).rotation, 0, "the floor did not")


func test_every_shipped_interactable_wants_a_floor() -> void:
	var catalog := load("res://data/arena_pieces/default_catalog.tres") as PieceCatalog
	for id: StringName in [&"bounce_pad", &"jump_link", &"zip_line",
			&"moving_platform", &"hazard_zone", &"ammo_pickup", &"snare_zone"]:
		var piece: PieceDefinition = catalog.get_piece(id)
		assert_not_null(piece, "%s is in the catalog" % id)
		assert_eq(piece.support, PieceDefinition.Support.FLOOR,
			"%s should sit on a floor" % id)
	for id: StringName in [&"wall_1x1", &"pillar_1x1", &"cover_low"]:
		assert_eq(catalog.get_piece(id).support, PieceDefinition.Support.ANY,
			"%s is structure and stacks freely" % id)


func test_the_shipped_anchor_hangs_high_and_free() -> void:
	var catalog := load("res://data/arena_pieces/default_catalog.tres") as PieceCatalog
	var anchor: PieceDefinition = catalog.get_piece(&"grapple_anchor")
	assert_eq(anchor.support, PieceDefinition.Support.EMPTY,
		"an anchor on the floor is a decoration, not a grapple target")
	assert_gte(anchor.min_level, 2, "and it has to be over the player's head")


func test_an_anchor_needs_an_empty_cell() -> void:
	var model: PlacementModel = _interactable_model()
	assert_true(model.place(&"anchor", Vector3i(2, 2, 2)), "empty air, high enough")
	model.place(&"floor", Vector3i(3, 2, 3))
	assert_eq(model.refusal_for(&"anchor", Vector3i(3, 2, 3)), &"needs_empty",
		"not on top of a floor tile: it is meant to hang")


func test_an_anchor_is_refused_below_its_level() -> void:
	var model: PlacementModel = _interactable_model()
	assert_eq(model.refusal_for(&"anchor", Vector3i(2, 1, 2)), &"too_low")
	assert_eq(model.refusal_for(&"anchor", Vector3i(2, 0, 2)), &"too_low")


func test_two_anchors_still_cannot_share_a_cell() -> void:
	var model: PlacementModel = _interactable_model()
	model.place(&"anchor", Vector3i(2, 2, 2))
	assert_eq(model.refusal_for(&"anchor", Vector3i(2, 2, 2)), &"cell_taken")
