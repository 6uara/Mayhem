@tool
extends SceneTree
## Builds the arena a normal run happens in, with the same PlacementModel the
## editor uses. Run headless:
##   godot --headless --path . -s tools/make_default_arena.gd
##
## The greybox arena it replaces was a hand-built scene; this is data, so it can
## be opened in the arena editor, played, and changed without touching a scene
## file. What it keeps from the greybox is the shape of the fight: a wide floor,
## two raised levels reached by ramps and pads, cover to break sightlines, and
## seven spawn doors spread so no camping spot covers them all.

const CATALOG_PATH: String = "res://data/arena_pieces/default_catalog.tres"
const OUT_PATH: String = "res://data/arenas/default_arena.tres"

## 24x24 cells of 4m: a 96m floor, the size the greybox played at.
const GRID: Vector3i = Vector3i(24, 8, 24)
const FLOOR: int = 18
## The raised walkway runs along two edges, one level up.
const LEDGE_LEVEL: int = 1
## The perch above the middle, two levels up, reached by pads.
const PERCH_LEVEL: int = 2

var _model: PlacementModel
var _failures: int = 0


func _initialize() -> void:
	var catalog := load(CATALOG_PATH) as PieceCatalog
	if catalog == null:
		push_error("make_default_arena: no catalog at %s" % CATALOG_PATH)
		quit(1)
		return

	var arena := ArenaData.new()
	arena.arena_name = "The Pit"
	arena.grid_size = GRID
	# The tiled venue: sections repeated to the arena's real size, which is the
	# only way the stands land on it exactly at any size.
	arena.theme_id = &"tiled"
	arena.author = "mayhem"
	arena.created_at = Time.get_datetime_string_from_system(true)
	_model = PlacementModel.new(arena, catalog)

	_build_floor()
	_build_ledges()
	_build_perch()
	_build_cover()
	_build_traversal()
	_build_pickups()
	_build_spawns()

	if _failures > 0:
		push_error("%d placements were refused; the arena is not what this script says" % _failures)
		quit(1)
		return

	var issues: Array[ValidationIssue] = ArenaValidator.validate(arena, catalog)
	for issue: ValidationIssue in issues:
		print("%s %s: %s" % [
			"ERROR " if issue.is_error() else "WARN  ", issue.code, issue.message])
	if not ArenaValidator.errors(issues).is_empty():
		push_error("make_default_arena: the arena does not validate")
		quit(1)
		return

	var graph: GridGraph = GridGraph.build(arena, catalog)
	print("pieces: %d | walkable: %d | enemy spawns: %d | nav links: %d" % [
		arena.placements.size(), graph.walkable_cells().size(),
		arena.enemy_spawns.size(), graph.shared_links().size()])
	var error: Error = ArenaIO.save(arena, OUT_PATH)
	print("saved %s (%d)" % [OUT_PATH, error])
	quit(0 if error == OK else 1)


# Private

## Placing through here rather than `model.place` directly: a refusal used to be
## a silently missing piece, and an arena that quietly lost its anchors still
## saved and still validated. Now the build fails and says which cell.
func _place(piece_id: StringName, cell: Vector3i, rotation: int = 0) -> void:
	var refusal: StringName = _model.refusal_for(piece_id, cell, rotation)
	if refusal != &"":
		push_error("%s at %s refused: %s" % [piece_id, cell, refusal])
		_failures += 1


func _build_floor() -> void:
	for x: int in FLOOR:
		for z: int in FLOOR:
			_place(&"floor_1x1", Vector3i(x, 0, z))


## A walkway one level up around all four sides, two cells wide: the outer row
## carries the railing, the inner row stays clear so the walkway is a route and
## not a chain of two-cell islands. Ramps at the four corners.
func _build_ledges() -> void:
	var outer: Array[int] = [1, FLOOR - 2]
	var inner: Array[int] = [2, FLOOR - 3]
	for x: int in range(1, FLOOR - 1):
		for z: int in outer + inner:
			_place(&"floor_1x1", Vector3i(x, LEDGE_LEVEL, z))
	for z: int in range(3, FLOOR - 3):
		for x: int in outer + inner:
			_place(&"floor_1x1", Vector3i(x, LEDGE_LEVEL, z))
	for cell: Vector3i in [
		Vector3i(3, LEDGE_LEVEL, 3), Vector3i(FLOOR - 4, LEDGE_LEVEL, 3),
		Vector3i(3, LEDGE_LEVEL, FLOOR - 4), Vector3i(FLOOR - 4, LEDGE_LEVEL, FLOOR - 4),
	]:
		_place(&"ramp_1x1", cell)
	# Railing on the outer row only, so it never cuts the path. The four corner
	# cells belong to the north and south rows; the side rows skip them rather
	# than trying to put a second post in an occupied cell.
	for i: int in range(1, FLOOR - 1, 3):
		_place(&"cover_low", Vector3i(i, LEDGE_LEVEL, 1))
		_place(&"cover_low", Vector3i(i, LEDGE_LEVEL, FLOOR - 2))
		if i == 1 or i == FLOOR - 2:
			continue
		_place(&"cover_low", Vector3i(1, LEDGE_LEVEL, i))
		_place(&"cover_low", Vector3i(FLOOR - 2, LEDGE_LEVEL, i))


## The high ground: worth taking, and exposed enough that holding it is a choice
## rather than a solution.
func _build_perch() -> void:
	for x: int in range(7, 11):
		for z: int in range(7, 11):
			_place(&"floor_1x1", Vector3i(x, PERCH_LEVEL, z))
	_place(&"cover_low", Vector3i(7, PERCH_LEVEL, 7))
	_place(&"cover_low", Vector3i(10, PERCH_LEVEL, 10))


func _build_cover() -> void:
	for cell: Vector3i in [
		Vector3i(5, 0, 5), Vector3i(12, 0, 5), Vector3i(5, 0, 12), Vector3i(12, 0, 12),
		Vector3i(8, 0, 3), Vector3i(9, 0, 14),
	]:
		_place(&"cover_low", cell)
	for cell: Vector3i in [Vector3i(4, 0, 8), Vector3i(13, 0, 9)]:
		_place(&"pillar_1x1", cell)
	# Two short walls across the middle, so the floor is never one open shooting
	# gallery from corner to corner.
	for z: int in range(7, 10):
		_place(&"wall_1x1", Vector3i(6, 0, z))
		_place(&"wall_1x1", Vector3i(11, 0, z))
	_place(&"hazard_zone", Vector3i(8, 0, 8))
	_place(&"hazard_zone", Vector3i(9, 0, 9))


## Pads to the perch, jump links the horde can use to reach the walkway, and
## anchors for the grapple.
func _build_traversal() -> void:
	for cell: Vector3i in [Vector3i(7, 0, 10), Vector3i(10, 0, 7)]:
		_place(&"bounce_pad", cell)
	# One per side, rotated so each lands on the walkway behind it: the link is
	# (0, +1, +2) unrotated, and a quarter turn moves it around the arena.
	_place(&"jump_link", Vector3i(6, 0, 4), 2)
	_place(&"jump_link", Vector3i(11, 0, FLOOR - 5), 0)
	_place(&"jump_link", Vector3i(4, 0, 11), 1)
	_place(&"jump_link", Vector3i(FLOOR - 5, 0, 6), 3)
	# Anchors hang over open floor, a level above the perch: the point of one is
	# to be above you, so they go in empty cells rather than on a surface.
	for cell: Vector3i in [
		Vector3i(4, PERCH_LEVEL + 1, 4), Vector3i(13, PERCH_LEVEL + 1, 13),
		Vector3i(4, PERCH_LEVEL + 1, 13), Vector3i(13, PERCH_LEVEL + 1, 4),
	]:
		_place(&"grapple_anchor", cell)


func _build_pickups() -> void:
	for cell: Vector3i in [
		Vector3i(5, 0, 8), Vector3i(12, 0, 9), Vector3i(8, 0, 5), Vector3i(9, 0, 12),
		Vector3i(8, PERCH_LEVEL, 9), Vector3i(2, LEDGE_LEVEL, 8),
	]:
		_place(&"ammo_pickup", cell)


## Seven, because the authored waves name door_01 through door_07 and the loader
## numbers doors in the order the spawns are listed here.
func _build_spawns() -> void:
	_model.set_player_spawn(Vector3i(8, 0, 12))
	for cell: Vector3i in [
		Vector3i(4, 0, 4), Vector3i(13, 0, 4), Vector3i(4, 0, 13), Vector3i(13, 0, 13),
		Vector3i(8, 0, 0), Vector3i(0, 0, 9), Vector3i(17, 0, 8),
	]:
		_model.add_enemy_spawn(cell)
