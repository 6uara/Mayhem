extends GutTest
## The editor has to show where a moving platform goes, both for the one being
## placed and for the ones already down. Without it the only way to learn its
## path was to press Play.

const CATALOG: String = "res://data/arena_pieces/default_catalog.tres"

var _preview: ArenaPreview
var _model: PlacementModel


func before_each() -> void:
	var arena := ArenaData.new()
	arena.grid_size = Vector3i(12, 6, 12)
	_model = PlacementModel.new(arena, load(CATALOG) as PieceCatalog)
	_preview = ArenaPreview.new()
	_preview.model = _model
	add_child_autofree(_preview)


func _find(node: Node, node_name: String) -> Node:
	if node.name == node_name:
		return node
	for child: Node in node.get_children():
		var found: Node = _find(child, node_name)
		if found != null:
			return found
	return null


func test_a_placed_platform_draws_its_path_and_stays_put() -> void:
	assert_true(_model.place(&"moving_platform", Vector3i(5, 1, 2), 1), "precondition: it fits")
	_preview.rebuild()
	var path := _find(_preview, "TravelPath") as Node3D
	assert_not_null(path, "the path is drawn")
	var platform: MovingPlatform = null
	for child: Node in _preview.get_node("Geometry").get_children():
		if child is MovingPlatform:
			platform = child
	assert_not_null(platform)
	assert_eq(platform.process_mode, Node.PROCESS_MODE_DISABLED,
		"a platform driving around the editor cannot be aimed at")
	# Rotation 1 sends it to -X: the arrival slab sits three cells that way.
	var arrival := path.get_node("Arrival") as Node3D
	var cell_size: Vector3 = _model.catalog.cell_size
	assert_almost_eq(arrival.position.x, platform.position.x - 3.0 * cell_size.x, 0.01)
	assert_almost_eq(arrival.position.z, platform.position.z, 0.01)


func test_the_ghost_shows_the_path_it_would_take() -> void:
	_preview.show_ghost(&"moving_platform", Vector3i(2, 1, 2), 0, true)
	assert_not_null(_find(_preview, "TravelPath"), "placing shows where it goes")


func test_other_pieces_draw_no_path() -> void:
	_model.place(&"wall_1x1", Vector3i(2, 0, 2))
	_preview.rebuild()
	_preview.show_ghost(&"wall_1x1", Vector3i(4, 0, 4), 0, true)
	assert_null(_find(_preview, "TravelPath"))
