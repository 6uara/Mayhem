extends GutTest
## The venue assembled from sections: it has to fit any arena exactly, which is
## the whole reason it exists next to the single-bowl shell.

const SHELL_SCENE: String = "res://scenes/arena/shells/tiled_shell.tscn"


func _shell() -> ArenaTiledShell:
	var scene := load(SHELL_SCENE) as PackedScene
	var shell := scene.instantiate() as ArenaTiledShell
	add_child_autofree(shell)
	return shell


func _stands(shell: ArenaTiledShell) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for child: Node in shell.get_node("Ring").get_children():
		if child.name.begins_with("Stand") or child.name.begins_with("Corner"):
			found.append(child as Node3D)
	return found


func test_the_ring_is_built_from_sections_and_four_corners() -> void:
	var shell: ArenaTiledShell = _shell()
	shell.setup(AABB(Vector3.ZERO, Vector3(64.0, 24.0, 64.0)))
	var corners: int = 0
	var stands: int = 0
	for node: Node3D in _stands(shell):
		if node.name.begins_with("Corner"):
			corners += 1
		else:
			stands += 1
	assert_eq(corners, 4, "one per corner")
	assert_gt(stands, 3, "at least one straight run per side")


func test_the_ring_hugs_the_arena_it_was_given() -> void:
	var shell: ArenaTiledShell = _shell()
	var bounds := AABB(Vector3(-2.0, 0.0, -2.0), Vector3(64.0, 24.0, 64.0))
	shell.setup(bounds)
	var ring: AABB = shell.get_ring_bounds()
	var centre: Vector3 = bounds.position + bounds.size * 0.5
	var ring_centre: Vector3 = ring.position + ring.size * 0.5
	assert_almost_eq(ring_centre.x, centre.x, 0.5, "centred on the arena, not offset")
	assert_almost_eq(ring_centre.z, centre.z, 0.5)
	assert_gt(ring.size.x, bounds.size.x, "and it surrounds it")
	assert_lt(ring.size.x, bounds.size.x + 100.0, "without towering over it")


func test_it_fits_a_second_arena_without_being_rebuilt_by_hand() -> void:
	var shell: ArenaTiledShell = _shell()
	shell.setup(AABB(Vector3.ZERO, Vector3(64.0, 24.0, 64.0)))
	var small: Vector3 = shell.get_ring_bounds().size
	shell.setup(AABB(Vector3.ZERO, Vector3(128.0, 24.0, 128.0)))
	var large: Vector3 = shell.get_ring_bounds().size
	assert_gt(large.x, small.x + 50.0, "the ring grew with the arena")
	assert_eq(shell.get_node("Ring").get_child_count() > 8, true,
		"and it grew by adding sections")


func test_a_rectangular_arena_gets_a_rectangular_ring() -> void:
	var shell: ArenaTiledShell = _shell()
	shell.setup(AABB(Vector3.ZERO, Vector3(96.0, 24.0, 48.0)))
	var ring: AABB = shell.get_ring_bounds()
	assert_gt(ring.size.x, ring.size.z + 30.0,
		"no single-bowl proportion to fight: the ring is whatever shape the arena is")


func test_sections_are_never_stretched_past_the_limit() -> void:
	var shell: ArenaTiledShell = _shell()
	shell.setup(AABB(Vector3.ZERO, Vector3(70.0, 24.0, 70.0)))
	for node: Node3D in _stands(shell):
		if node.name.begins_with("Corner"):
			continue
		assert_between(node.scale.x, 0.5, shell.max_section_stretch * shell.section_scale,
			"%s is stretched out of shape" % node.name)


func test_the_venue_still_walls_the_player_in_and_floors_the_gap() -> void:
	var shell: ArenaTiledShell = _shell()
	shell.setup(AABB(Vector3.ZERO, Vector3(64.0, 24.0, 64.0)))
	assert_eq(shell.get_node("Ring/Perimeter").get_child_count(), 4)
	var aprons: int = 0
	for child: Node in shell.get_node("Ring").get_children():
		if child.name.begins_with("Apron"):
			aprons += 1
	assert_eq(aprons, 4, "a ring of slabs, never a slab under the arena")
