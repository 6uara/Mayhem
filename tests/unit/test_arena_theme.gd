extends GutTest
## The venue around an authored arena: what surrounds it, and what happens to
## anything that falls off it.


func test_there_is_always_a_theme_to_use() -> void:
	var themes: Array[ArenaTheme] = ArenaTheme.list_themes()
	assert_gt(themes.size(), 0, "list_themes never comes back empty")


func test_the_shipped_default_theme_loads() -> void:
	var theme: ArenaTheme = ArenaTheme.find(&"default")
	assert_eq(theme.id, &"default")
	assert_gt(theme.kill_plane_depth, 0.0, "falling has to end somewhere")


func test_an_unknown_theme_falls_back_instead_of_failing() -> void:
	var theme: ArenaTheme = ArenaTheme.find(&"no_such_venue")
	assert_not_null(theme, "a renamed theme file must not stop an arena loading")


func test_a_theme_without_an_environment_builds_one() -> void:
	var theme := ArenaTheme.new()
	assert_null(theme.environment)
	var built: Environment = theme.get_environment()
	assert_not_null(built)
	assert_eq(built.background_mode, Environment.BG_COLOR,
		"the fallback matches the greybox arena, so an unthemed arena is still lit")


func test_the_bounds_cover_the_whole_grid() -> void:
	var arena := ArenaData.new()
	arena.grid_size = Vector3i(24, 8, 24)
	var catalog := PieceCatalog.new()
	catalog.cell_size = Vector3(4.0, 3.0, 4.0)

	var runtime := ArenaRuntime.new()
	autofree(runtime)
	runtime.setup(arena, catalog)
	var bounds: AABB = runtime.get_bounds()
	assert_eq(bounds.size, Vector3(96.0, 24.0, 96.0), "grid_size in metres")
	assert_true(bounds.has_point(catalog.cell_to_world(Vector3i(23, 0, 23))),
		"the far corner cell is inside the footprint a shell is handed")


func _shell() -> ArenaShell:
	var scene := load("res://scenes/arena/shells/default_shell.tscn") as PackedScene
	var shell := scene.instantiate() as ArenaShell
	add_child_autofree(shell)
	return shell


func test_the_default_theme_carries_the_stands() -> void:
	var theme: ArenaTheme = ArenaTheme.find(&"default")
	assert_not_null(theme.shell_scene, "the venue is what stops the arena floating in sky")


func test_the_shell_centres_its_pit_on_the_arena() -> void:
	var shell: ArenaShell = _shell()
	var bounds := AABB(Vector3(-2.0, 0.0, -2.0), Vector3(64.0, 24.0, 64.0))
	shell.setup(bounds)

	var stands: Node3D = shell.get_node("Stands")
	var centre: Vector3 = bounds.position + bounds.size * 0.5
	var pit_centre := Vector3(
		stands.position.x + shell.pit_center.x * stands.scale.x,
		0.0,
		stands.position.z + shell.pit_center.y * stands.scale.z)
	assert_almost_eq(pit_centre.x, centre.x, 0.01)
	assert_almost_eq(pit_centre.z, centre.z, 0.01)


func test_the_pit_is_wider_than_the_arena_by_the_margin() -> void:
	var shell: ArenaShell = _shell()
	var bounds := AABB(Vector3.ZERO, Vector3(64.0, 24.0, 64.0))
	shell.setup(bounds)
	var stands: Node3D = shell.get_node("Stands")
	assert_almost_eq(shell.pit_size.x * stands.scale.x,
		bounds.size.x + shell.pit_margin * 2.0, 0.01)
	assert_almost_eq(shell.pit_size.y * stands.scale.z,
		bounds.size.z + shell.pit_margin * 2.0, 0.01)


func test_a_uniform_fit_never_shrinks_the_pit_below_the_arena() -> void:
	var shell: ArenaShell = _shell()
	shell.uniform_fit = true
	var bounds := AABB(Vector3.ZERO, Vector3(64.0, 24.0, 64.0))
	shell.setup(bounds)
	var stands: Node3D = shell.get_node("Stands")
	assert_eq(stands.scale.x, stands.scale.z, "same scale on both axes")
	assert_gte(shell.pit_size.x * stands.scale.x, bounds.size.x)
	assert_gte(shell.pit_size.y * stands.scale.z, bounds.size.z)


func test_the_shell_walls_the_play_area_in() -> void:
	var shell: ArenaShell = _shell()
	shell.setup(AABB(Vector3.ZERO, Vector3(64.0, 24.0, 64.0)))
	var perimeter: Node = shell.get_node_or_null("Perimeter")
	assert_not_null(perimeter, "the arena edge cannot be an open cliff")
	assert_eq(perimeter.get_child_count(), 4)
	for wall: Node in perimeter.get_children():
		assert_true(wall is StaticBody3D)
		assert_false(wall.is_in_group(ArenaRuntime.NAVIGATION_SOURCE_GROUP),
			"walls must stay out of the navmesh bake")


func test_the_apron_rings_the_arena_without_covering_it() -> void:
	var shell: ArenaShell = _shell()
	var bounds := AABB(Vector3.ZERO, Vector3(64.0, 24.0, 64.0))
	shell.setup(bounds)
	var apron: Node3D = shell.get_node_or_null("Apron") as Node3D
	assert_not_null(apron, "without it the ring around the arena is a moat of sky")
	assert_eq(apron.get_child_count(), 4, "a ring, not a slab")

	# The slab under the arena is what z-fought the player's floor tiles, so no
	# piece of the apron may reach the middle.
	var arena_centre: Vector3 = bounds.position + bounds.size * 0.5
	for slab: MeshInstance3D in apron.get_children():
		var size: Vector3 = (slab.mesh as BoxMesh).size
		var covers_x: bool = absf(slab.position.x - arena_centre.x) < size.x * 0.5
		var covers_z: bool = absf(slab.position.z - arena_centre.z) < size.z * 0.5
		assert_false(covers_x and covers_z,
			"%s sits over the arena floor" % slab.name)


func test_the_apron_reaches_from_the_arena_to_the_stands() -> void:
	var shell: ArenaShell = _shell()
	var bounds := AABB(Vector3.ZERO, Vector3(64.0, 24.0, 64.0))
	shell.setup(bounds)
	var north: MeshInstance3D = shell.get_node("Apron/Apron0") as MeshInstance3D
	assert_almost_eq((north.mesh as BoxMesh).size.z, shell.pit_margin, 0.01,
		"the band is exactly the margin the pit adds")


func test_the_stands_are_drawn_from_both_sides_while_the_normals_are_broken() -> void:
	var shell: ArenaShell = _shell()
	assert_true(shell.double_sided,
		"the shipped bowl has inverted faces; culling them leaves holes")
	var stands: Node3D = shell.get_node("Stands")
	var mesh: MeshInstance3D = stands.get_child(0) as MeshInstance3D
	var material := mesh.material_override as StandardMaterial3D
	assert_not_null(material, "the shell paints the stands itself")
	assert_eq(material.cull_mode, BaseMaterial3D.CULL_DISABLED)


func test_a_pit_shaped_like_the_arena_does_not_stretch() -> void:
	var theme := ArenaTheme.new()
	theme.pit_size = Vector2(20.0, 10.0)
	assert_almost_eq(theme.get_stretch(Vector2(80.0, 40.0)), 1.0, 0.01,
		"same proportions, same scale on both axes")


func test_a_square_arena_in_a_two_to_one_pit_stretches_twice() -> void:
	var theme := ArenaTheme.new()
	theme.pit_size = Vector2(20.0, 10.0)
	assert_almost_eq(theme.get_stretch(Vector2(80.0, 80.0)), 2.0, 0.01)


func test_the_suggested_footprint_is_the_one_that_fits() -> void:
	var theme := ArenaTheme.new()
	theme.pit_size = Vector2(19.0, 9.5)
	var suggested: Vector2 = theme.suggest_footprint(96.0)
	assert_almost_eq(suggested.x, 96.0, 0.01)
	assert_almost_eq(suggested.y, 48.0, 0.01, "half, like the pit")
	assert_almost_eq(theme.get_stretch(suggested), 1.0, 0.01,
		"and building that shape costs the venue nothing")


func test_the_shell_takes_its_pit_from_the_theme() -> void:
	var shell: ArenaShell = _shell()
	var theme := ArenaTheme.new()
	theme.pit_size = Vector2(40.0, 40.0)
	theme.pit_center = Vector2.ZERO
	shell.setup(AABB(Vector3.ZERO, Vector3(64.0, 24.0, 64.0)), theme)
	assert_eq(shell.pit_size, Vector2(40.0, 40.0),
		"one measurement, and the theme owns it")
	var stands: Node3D = shell.get_node("Stands")
	assert_almost_eq(stands.scale.x, stands.scale.z, 0.01,
		"a square pit around a square arena scales evenly")
