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
	# Cuatro por anillo: el venue apila anillos para trepar como un coliseo, asi
	# que "una esquina por esquina" es por tier y no en total.
	assert_eq(corners, 4 * shell.tiers, "one per corner, per tier")
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


# El coliseo

func test_the_venue_stacks_rings_into_something_that_towers() -> void:
	# Un solo anillo de 12 metros alrededor de una arena de 70 se lee como un
	# paredon con escalones: desde el piso se ve el cielo justo arriba del borde.
	# Apilar anillos es lo que hace que el lugar encierre.
	var shell: ArenaTiledShell = _shell()
	shell.tiers = 3
	shell.setup(AABB(Vector3.ZERO, Vector3(64.0, 24.0, 64.0)))
	var single: ArenaTiledShell = _shell()
	single.tiers = 1
	single.setup(AABB(Vector3.ZERO, Vector3(64.0, 24.0, 64.0)))

	var tall: float = shell.get_ring_bounds().size.y
	var short: float = single.get_ring_bounds().size.y
	assert_gt(tall, short * 2.0, "tres anillos tienen que trepar bastante mas que uno")


func test_every_ring_sits_further_out_than_the_one_below() -> void:
	# Sin esto los anillos se apilan rectos y la tribuna sale como una torre en
	# vez de como una tribuna.
	var shell: ArenaTiledShell = _shell()
	shell.tiers = 3
	shell.setup(AABB(Vector3.ZERO, Vector3(64.0, 24.0, 64.0)))
	var widest_by_tier: Dictionary = {}
	for node: Node3D in _stands(shell):
		var tier: int = int(node.name.get_slice("_", 0).lstrip("StandCorner"))
		var reach: float = absf((node.transform * _bounds_of(node)).end.z)
		widest_by_tier[tier] = maxf(float(widest_by_tier.get(tier, 0.0)), reach)
	assert_eq(widest_by_tier.size(), 3, "un anillo por tier")
	assert_gt(float(widest_by_tier[1]), float(widest_by_tier[0]))
	assert_gt(float(widest_by_tier[2]), float(widest_by_tier[1]))


func test_the_shell_tells_the_crowd_where_the_seats_are() -> void:
	# Es el shell el que apila los anillos, asi que es el unico que sabe donde
	# quedaron los escalones. Que la tribuna lo adivine es lo que tenia a la
	# gente flotando delante de la grada.
	var shell: ArenaTiledShell = _shell()
	var crowd := CrowdStands.new()
	shell.add_child(crowd)
	shell.crowd = crowd
	shell.tiers = 3
	shell.rows_per_tier = 4
	shell.setup(AABB(Vector3.ZERO, Vector3(64.0, 24.0, 64.0)))

	assert_true(crowd.has_seats(), "el shell tiene que haber sembrado la tribuna")
	var heights: Array[float] = []
	for seat: Vector3 in crowd.get_seats():
		if not heights.has(seat.y):
			heights.append(seat.y)
	assert_eq(heights.size(), 12, "tres anillos por cuatro filas cada uno")


func _bounds_of(node: Node3D) -> AABB:
	var found := AABB()
	var first: bool = true
	for child: Node in node.get_children():
		var mesh := child as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var box: AABB = mesh.transform * mesh.mesh.get_aabb()
		found = box if first else found.merge(box)
		first = false
	return found
