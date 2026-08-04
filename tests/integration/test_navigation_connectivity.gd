extends GutTest
## Can an enemy actually path from the floor up to each raised level?
##
## A navmesh can be non-empty, span the arena and still be a set of disconnected
## islands. When that happens the agent paths to the edge of its island and stops -
## which reads in play as "enemies get stuck beside the ramp instead of using it".

const GROUND := Vector3(0, 0.2, 20)

## Ceiling on the wait for NavigationServer3D to register the arena's region. Well
## past what it has ever needed - this is a guard against hanging, not a timing
## assumption.
const MAX_SYNC_FRAMES: int = 120

## Destinations that can only be reached by walking up something.
const RAISED := {
	"mid west platform": Vector3(-24, 3.4, -8),
	"mid east platform": Vector3(24, 3.4, 4),
	"high walkway": Vector3(0, 6.4, -30),
	"high perch": Vector3(6, 6.4, 6),
}

var _map: RID


## Built per test rather than once for the script.
##
## This is what the "flaky navmesh" actually was. Doing this in before_all looked
## right and passed whenever some earlier test had already put an arena in the tree,
## which is why it failed intermittently and never in isolation - run on its own,
## this file failed every single time. The region registers correctly from inside a
## test; from before_all the server never picks it up. Paying for the arena five
## times is worth a suite that means what it says.
func before_each() -> void:
	var arena: Node = add_child_autofree(
		load("res://scenes/arena/greybox_arena.tscn").instantiate())
	var region: NavigationRegion3D = arena.get_node("Navigation")
	_map = region.get_navigation_map()

	# The server still syncs on its own schedule, so wait on the map being usable
	# rather than on a frame count.
	for _i: int in MAX_SYNC_FRAMES:
		await wait_physics_frames(1)
		NavigationServer3D.map_force_update(_map)
		if NavigationServer3D.map_get_regions(_map).size() > 0 \
				and _snap(GROUND).distance_to(GROUND) < 2.0:
			return


func _snap(point: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(_map, point)


## Links have to be included, or this only measures walkable ground - and with the
## ramps removed, walkable ground alone reaches nothing.
func _path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var parameters := NavigationPathQueryParameters3D.new()
	parameters.map = _map
	parameters.start_position = _snap(from)
	parameters.target_position = _snap(to)
	parameters.path_postprocessing = NavigationPathQueryParameters3D.PATH_POSTPROCESSING_CORRIDORFUNNEL
	var result := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(parameters, result)
	return result.path


func test_the_arena_has_jump_links_where_ramps_used_to_be() -> void:
	var links: Array = get_tree().get_nodes_in_group(&"jump_link")
	assert_gt(links.size(), 0,
		"without ramps the raised levels are islands unless links bridge them")


func test_the_map_has_a_navmesh_at_all() -> void:
	assert_true(_map.is_valid(), "navigation map")
	assert_gt(NavigationServer3D.map_get_regions(_map).size(), 0, "regions")


func test_the_ground_is_walkable() -> void:
	var snapped: Vector3 = _snap(GROUND)
	assert_lt(snapped.distance_to(GROUND), 2.0,
		"the spawn floor should be on the navmesh")


## The load-bearing test. If these fail, enemies cannot follow the player upstairs
## no matter how good the behaviour trees are.
func test_every_raised_level_is_reachable_from_the_ground() -> void:
	for label: String in RAISED:
		var destination: Vector3 = RAISED[label]
		var snapped: Vector3 = _snap(destination)
		assert_lt(snapped.distance_to(destination), 3.0,
			"%s is not covered by the navmesh" % label)

		var path: PackedVector3Array = _path(GROUND, destination)
		assert_gt(path.size(), 1, "no path to the %s" % label)
		if path.size() < 1:
			continue
		assert_lt(path[path.size() - 1].distance_to(snapped), 3.0,
			"the path to the %s stops short - the navmesh is an island" % label)


func test_paths_upstairs_actually_climb() -> void:
	for label: String in RAISED:
		var path: PackedVector3Array = _path(GROUND, RAISED[label])
		if path.size() < 2:
			continue
		var highest: float = -INF
		for point: Vector3 in path:
			highest = maxf(highest, point.y)
		assert_gt(highest, 2.0, "the path to the %s never gains height" % label)
