extends GutTest
## The arena's navmesh has to actually contain the arena. An empty navmesh is silent:
## agents just report "navigation finished" and enemies fall back to straight-line
## steering, walking into walls instead of pathing around them.
##
## Re-run `tools/bake_navmesh.gd` and commit the result if this fails after a layout
## change - the committed bake is what ships.


func test_arena_has_a_populated_navmesh() -> void:
	var arena: Node3D = add_child_autofree(
		load("res://scenes/arena/greybox_arena.tscn").instantiate())
	var region := arena.get_node("Navigation") as NavigationRegion3D
	assert_not_null(region, "the arena has a NavigationRegion3D")

	await wait_physics_frames(2)

	var navmesh: NavigationMesh = region.navigation_mesh
	assert_not_null(navmesh, "navigation_mesh")
	assert_gt(navmesh.get_vertices().size(), 0,
		"empty navmesh - re-run tools/bake_navmesh.gd")
	assert_gt(navmesh.get_polygon_count(), 0, "empty navmesh - no polygons")


func test_navmesh_covers_the_arena_floor() -> void:
	var arena: Node3D = add_child_autofree(
		load("res://scenes/arena/greybox_arena.tscn").instantiate())
	await wait_physics_frames(2)

	# The floor is 70x70; a bake that only caught one platform would still pass the
	# "not empty" check, so assert it actually spans the play space.
	var navmesh: NavigationMesh = (arena.get_node("Navigation") as NavigationRegion3D).navigation_mesh
	var min_x: float = INF
	var max_x: float = -INF
	for vertex: Vector3 in navmesh.get_vertices():
		min_x = minf(min_x, vertex.x)
		max_x = maxf(max_x, vertex.x)
	assert_gt(max_x - min_x, 40.0, "the navmesh should span most of the 70m arena")


func test_spawn_doors_are_registered_and_unique() -> void:
	var arena: Node3D = add_child_autofree(
		load("res://scenes/arena/greybox_arena.tscn").instantiate())
	await wait_physics_frames(2)

	var doors: Array = get_tree().get_nodes_in_group(&"spawn_door")
	assert_gt(doors.size(), 1, "more than one door, or camping beats the level design")

	var ids: Array[StringName] = []
	for node: Node in doors:
		var door := node as SpawnDoor
		assert_not_null(door, "every member of the group is a SpawnDoor")
		assert_false(ids.has(door.door_id), "duplicate door id %s" % door.door_id)
		ids.push_back(door.door_id)
