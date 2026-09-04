@tool
extends SceneTree
## Builds the example arena that ships with the tools, by driving the same
## PlacementModel the editor dock drives. Run headless:
##   godot --headless --path . -s tools/make_example_arena.gd
##
## Doubles as the proof that `arena_editor/core/` is genuinely UI-free: this file
## builds, validates and saves a playable arena without an editor in sight.

const CATALOG_PATH: String = "res://data/arena_pieces/default_catalog.tres"
const OUT_PATH: String = "res://data/arenas/example_pit.tres"

const GRID: Vector3i = Vector3i(24, 8, 24)
## The pit: a 12x12 floor, a raised ledge along the north edge reached by ramps,
## cover in the middle, and a wall line that forces flanking.
const FLOOR_SIZE: int = 12
const LEDGE_ROW: int = 11
const RAMP_COLUMNS: Array[int] = [3, 8]

var _model: PlacementModel
var _failures: int = 0


func _initialize() -> void:
	var catalog := load(CATALOG_PATH) as PieceCatalog
	if catalog == null:
		push_error("make_example_arena: no catalog at %s" % CATALOG_PATH)
		quit(1)
		return

	var arena := ArenaData.new()
	arena.arena_name = "Example Pit"
	arena.grid_size = GRID
	arena.author = "mayhem_tools"
	arena.created_at = Time.get_datetime_string_from_system(true)
	_model = PlacementModel.new(arena, catalog)

	for x: int in FLOOR_SIZE:
		for z: int in FLOOR_SIZE:
			_place(&"floor_1x1", Vector3i(x, 0, z))
	for x: int in FLOOR_SIZE:
		_place(&"floor_1x1", Vector3i(x, 1, LEDGE_ROW))
	for column: int in RAMP_COLUMNS:
		_place(&"ramp_1x1", Vector3i(column, 1, LEDGE_ROW - 1))
	# Body pieces share the cell with the floor they stand on - that is the point
	# of the two layers.
	for x: int in [5, 6]:
		_place(&"wall_1x1", Vector3i(x, 0, 5))
	for cell: Vector3i in [Vector3i(2, 0, 2), Vector3i(9, 0, 3), Vector3i(4, 0, 8)]:
		_place(&"cover_low", cell)
	_place(&"pillar_1x1", Vector3i(7, 0, 8))

	# Traversal. The jump link lands on the ledge two cells north and one level up,
	# which is exactly the offset baked into jump_link.tscn - enemies get that one.
	# The pads and the anchor are the player's, and the validator knows the
	# difference.
	_place(&"jump_link", Vector3i(5, 0, 9))
	_place(&"bounce_pad", Vector3i(1, 0, 6))
	_place(&"bounce_pad", Vector3i(10, 0, 6))
	# Anchors hang: empty cell, two levels up, per the piece's own rule.
	_place(&"grapple_anchor", Vector3i(6, 2, 2))
	_place(&"hazard_zone", Vector3i(8, 0, 8))

	_model.set_player_spawn(Vector3i(1, 0, 1))
	_model.add_enemy_spawn(Vector3i(10, 0, 10))
	_model.add_enemy_spawn(Vector3i(1, 0, 10))
	_model.add_enemy_spawn(Vector3i(10, 0, 1))

	if _failures > 0:
		push_error("%d placements were refused; the arena is not what this script says" % _failures)
		quit(1)
		return

	var issues: Array[ValidationIssue] = ArenaValidator.validate(arena, catalog)
	for issue: ValidationIssue in issues:
		print("%s %s: %s" % [
			"ERROR " if issue.is_error() else "WARN  ", issue.code, issue.message])
	if not ArenaValidator.errors(issues).is_empty():
		push_error("make_example_arena: the arena does not validate")
		quit(1)
		return

	var graph_links: Array = GridGraph.build(arena, catalog).shared_links()
	print("shared navigation links: %d" % graph_links.size())
	var nav := NavGrid.from_arena(arena, catalog)
	var path: Array[Vector3i] = nav.find_path(arena.player_spawn, Vector3i(10, 0, 10))
	print("pieces: %d | walkable: %d | path player->spawn: %d cells" % [
		arena.placements.size(),
		GridGraph.build(arena, catalog).walkable_cells().size(),
		path.size()])

	var error: Error = ArenaIO.save(arena, OUT_PATH)
	print("saved %s (%d)" % [OUT_PATH, error])
	quit(0 if error == OK else 1)


## Placing through here rather than `model.place` directly: a refusal used to be
## a silently missing piece, and an arena that quietly lost its anchors still
## saved and still validated. Now the build fails and says which cell.
func _place(piece_id: StringName, cell: Vector3i, rotation: int = 0) -> void:
	var refusal: StringName = _model.refusal_for(piece_id, cell, rotation)
	if refusal != &"":
		push_error("%s at %s refused: %s" % [piece_id, cell, refusal])
		_failures += 1
