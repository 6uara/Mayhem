extends GutTest
## The moving platform in the arena editor: where it may go, the path it claims,
## and what the loader does with it.
##
## It is the one piece that occupies more than where it sits. A platform placed on
## the floor slid a slab along the ground into whatever was there, and nothing
## stopped a wall being built across its path afterwards.

const CATALOG: String = "res://data/arena_pieces/default_catalog.tres"

var _catalog: PieceCatalog


func before_all() -> void:
	_catalog = load(CATALOG) as PieceCatalog


func _model() -> PlacementModel:
	var arena := ArenaData.new()
	arena.grid_size = Vector3i(12, 6, 12)
	return PlacementModel.new(arena, _catalog)


# ------------------------------------------------------------------- the piece

func test_the_shipped_platform_hangs_from_the_second_level_up() -> void:
	var piece: PieceDefinition = _catalog.get_piece(&"moving_platform")
	assert_eq(piece.support, PieceDefinition.Support.EMPTY, "it goes in an empty cell")
	assert_eq(piece.min_level, 1, "level 0 is the floor: the first level it can go is 1")
	assert_true(piece.moves())


func test_its_path_turns_with_it() -> void:
	var piece: PieceDefinition = _catalog.get_piece(&"moving_platform")
	var ahead: Array[Vector3i] = piece.get_path_offsets(0)
	assert_eq(ahead.size(), int(piece.travel_cells.length()), "one cell per step")
	assert_eq(ahead[-1], piece.travel_cells, "and it ends at the far end")
	assert_eq(piece.get_travel(1), PieceDefinition.rotate_cell(piece.travel_cells, 1))


# ---------------------------------------------------------------- where it goes

func test_it_is_refused_at_floor_level() -> void:
	assert_eq(_model().refusal_for(&"moving_platform", Vector3i(2, 0, 2)), &"too_low")


func test_it_is_refused_on_a_floor_tile() -> void:
	var model: PlacementModel = _model()
	model.place(&"floor_1x1", Vector3i(2, 1, 2))
	assert_eq(model.refusal_for(&"moving_platform", Vector3i(2, 1, 2)), &"needs_empty")


func test_it_goes_in_an_empty_cell_with_a_clear_path() -> void:
	assert_eq(_model().refusal_for(&"moving_platform", Vector3i(2, 1, 2)), &"")


func test_a_blocked_path_refuses_it() -> void:
	var model: PlacementModel = _model()
	# Two cells ahead, on +Z: in the middle of the way, not at either end.
	model.place(&"wall_1x1", Vector3i(2, 1, 4))
	assert_eq(model.refusal_for(&"moving_platform", Vector3i(2, 1, 2)), &"path_blocked")


func test_a_floor_tile_on_the_path_blocks_it_too() -> void:
	var model: PlacementModel = _model()
	model.place(&"floor_1x1", Vector3i(2, 1, 5))
	assert_eq(model.refusal_for(&"moving_platform", Vector3i(2, 1, 2)), &"path_blocked",
		"the far end is part of the path")


func test_a_path_off_the_grid_refuses_it() -> void:
	assert_eq(_model().refusal_for(&"moving_platform", Vector3i(2, 1, 10)),
		&"path_out_of_bounds")


# ------------------------------------------------------------- the path it claims

func test_nothing_can_be_built_on_a_placed_platforms_path() -> void:
	var model: PlacementModel = _model()
	assert_true(model.place(&"moving_platform", Vector3i(2, 1, 2)))
	assert_eq(model.refusal_for(&"wall_1x1", Vector3i(2, 1, 4)), &"platform_path")
	assert_eq(model.refusal_for(&"floor_1x1", Vector3i(2, 1, 5)), &"platform_path",
		"ground pieces too: a tile there is a wall the platform hits")
	assert_eq(model.refusal_for(&"wall_1x1", Vector3i(3, 1, 4)), &"",
		"beside the path is fine")


func test_two_platforms_cannot_cross() -> void:
	var model: PlacementModel = _model()
	model.place(&"moving_platform", Vector3i(2, 1, 2))
	# Rotation 1 turns +Z into -X: from x=5 it runs over x=4, 3, 2 at z=4.
	assert_eq(model.refusal_for(&"moving_platform", Vector3i(5, 1, 4), 1), &"path_blocked")


func test_turning_it_into_a_wall_is_refused() -> void:
	var model: PlacementModel = _model()
	model.place(&"moving_platform", Vector3i(5, 1, 5))
	model.place(&"wall_1x1", Vector3i(4, 1, 5))
	assert_false(model.rotate_at(Vector3i(5, 1, 5)), "a quarter turn points it at the wall")
	assert_eq(model.get_entry_at(Vector3i(5, 1, 5)).rotation, 0, "and it keeps its heading")
	assert_true(model.rotate_at(Vector3i(5, 1, 5), 2), "the other way is clear")


func test_moving_it_carries_its_path() -> void:
	var model: PlacementModel = _model()
	model.place(&"moving_platform", Vector3i(2, 1, 2))
	assert_eq(model.move_to(Vector3i(2, 1, 2), Vector3i(7, 1, 2)), &"")
	assert_eq(model.refusal_for(&"wall_1x1", Vector3i(2, 1, 4)), &"", "the old path is free")
	assert_eq(model.refusal_for(&"wall_1x1", Vector3i(7, 1, 4)), &"platform_path")


func test_filling_a_level_with_floor_leaves_the_path_open() -> void:
	var model: PlacementModel = _model()
	model.place(&"moving_platform", Vector3i(2, 1, 2))
	model.fill_floor(1)
	assert_null(model.get_entry_at(Vector3i(2, 1, 2), true), "nothing under the platform")
	for offset: Vector3i in _catalog.get_piece(&"moving_platform").get_path_offsets(0):
		assert_null(model.get_entry_at(Vector3i(2, 1, 2) + offset),
			"%s stays empty" % (Vector3i(2, 1, 2) + offset))


## Girar tiene que girar la pieza que se eligio. Antes lo hacia buscandola de
## nuevo por su celda de origen, y si en esa celda habia algo apoyado, giraba eso.
func test_rotating_a_floor_turns_the_floor_and_not_what_stands_on_its_origin() -> void:
	var model: PlacementModel = _model()
	model.place(&"floor_3x3", Vector3i(2, 0, 2))
	model.place(&"cover_low", Vector3i(2, 0, 2))
	assert_true(model.rotate_at(Vector3i(3, 0, 3)), "clicked the middle of the floor")
	assert_eq(model.get_entry_at(Vector3i(2, 0, 2), true).rotation, 1, "the floor turned")
	assert_eq(model.get_entry_at(Vector3i(2, 0, 2), false).rotation, 0, "the cover did not")


# ------------------------------------------------------------------- validation

func test_an_old_arena_with_a_blocked_path_is_warned_about() -> void:
	var model: PlacementModel = _model()
	model.arena.placements.append(PlacementEntry.make(&"moving_platform", Vector3i(2, 1, 2), 0))
	model.arena.placements.append(PlacementEntry.make(&"wall_1x1", Vector3i(2, 1, 3), 0))
	var codes: Array[StringName] = []
	for issue: ValidationIssue in ArenaValidator.validate(model.arena, _catalog):
		codes.append(issue.code)
	assert_true(codes.has(&"platform_path_blocked"))


func test_the_shipped_arenas_platforms_have_clear_paths() -> void:
	var arena: ArenaData = ArenaIO.load_arena("res://data/arenas/default_arena.tres")
	var platforms: int = 0
	for entry: PlacementEntry in arena.placements:
		if entry.piece_id == &"moving_platform":
			platforms += 1
			assert_gte(entry.cell.y, 1, "no platform left sliding along the floor")
	assert_gt(platforms, 0)
	for issue: ValidationIssue in ArenaValidator.validate(arena, _catalog):
		assert_ne(issue.code, &"platform_path_blocked", issue.message)
