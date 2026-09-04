extends GutTest
## The loader, end to end: an arena file becomes geometry, spawn doors, links and
## a kill zone under a parent node.

var _parent: Node3D


func before_each() -> void:
	_parent = Node3D.new()
	add_child_autofree(_parent)


## The one arena that ships. It is both the default a run happens in and the
## example the tools are exercised against, so there is nothing to keep in sync.
func _default() -> ArenaData:
	return ArenaIO.load_arena("res://data/arenas/default_arena.tres")


func test_the_example_arena_loads() -> void:
	var runtime: ArenaRuntime = ArenaLoader.load_arena(
		_default(), _parent, ArenaSession.catalog)
	assert_not_null(runtime, "the arena every run happens in has to stay playable")
	var arena: ArenaData = _default()
	assert_eq(runtime.geometry_root.get_child_count(), arena.placements.size(),
		"one node per placed piece")
	assert_eq(runtime.spawn_doors_root.get_child_count(), arena.enemy_spawns.size(),
		"one door per enemy spawn")


func test_a_broken_arena_never_loads() -> void:
	var arena := ArenaData.new()
	arena.grid_size = Vector3i(8, 4, 8)
	assert_null(ArenaLoader.load_arena(arena, _parent, ArenaSession.catalog),
		"no spawns, no arena")
	assert_push_error("blocking issue", "and it says why rather than failing quietly")


func test_shared_links_become_navigation_links() -> void:
	var runtime: ArenaRuntime = ArenaLoader.load_arena(
		_default(), _parent, ArenaSession.catalog)
	var links: Node = runtime.get_node_or_null("NavigationLinks")
	assert_not_null(links)
	var shared: int = GridGraph.build(_default(), ArenaSession.catalog).shared_links().size()
	assert_eq(links.get_child_count(), shared,
		"the jump links, both directions each - and none of the bounce pads")
	assert_gt(shared, 0, "the arena has links the horde can use")
	for child: Node in links.get_children():
		assert_true(child is NavigationLink3D)


func test_the_arena_carries_its_own_venue() -> void:
	var runtime: ArenaRuntime = ArenaLoader.load_arena(
		_default(), _parent, ArenaSession.catalog)
	assert_not_null(runtime.get_node_or_null("WorldEnvironment"), "sky and ambient")
	assert_not_null(runtime.get_node_or_null("Sun"), "a light of its own")
	var kill: Node3D = runtime.get_node_or_null("KillZone") as Node3D
	assert_not_null(kill, "falling off the edge has to end")
	assert_lt(kill.position.y, 0.0, "the kill volume sits under the arena")


func test_spawns_land_on_the_surface_not_inside_it() -> void:
	var runtime: ArenaRuntime = ArenaLoader.load_arena(
		_default(), _parent, ArenaSession.catalog)
	var spawn: Vector3 = runtime.get_player_spawn()
	assert_gt(spawn.y, 0.0, "feet on top of the floor tile, not in it")
	assert_lt(spawn.y, ArenaSession.catalog.cell_size.y, "and not floating a level up")


func test_the_venue_frames_what_was_built_not_the_empty_grid() -> void:
	var arena: ArenaData = _default()
	var runtime: ArenaRuntime = ArenaLoader.load_arena(arena, _parent, ArenaSession.catalog)
	var grid: AABB = runtime.get_bounds()
	var content: AABB = runtime.get_content_bounds()
	assert_lt(content.size.x, grid.size.x,
		"The Pit fills part of its grid, so the stands hug the part that exists")
	assert_true(grid.encloses(content))


func test_an_empty_arena_falls_back_to_the_grid() -> void:
	var arena := ArenaData.new()
	arena.grid_size = Vector3i(16, 6, 16)
	var runtime := ArenaRuntime.new()
	autofree(runtime)
	runtime.setup(arena, ArenaSession.catalog)
	assert_eq(runtime.get_content_bounds(), runtime.get_bounds())


## Venue-agnostic on purpose: which shell a theme names is the arena's business,
## and the loader's job is only to instance it and hand it the size. Asking for
## the tiled shell's node names here would break the day an arena picks the bowl.
func test_the_shell_is_instanced_and_fitted() -> void:
	var runtime: ArenaRuntime = ArenaLoader.load_arena(
		_default(), _parent, ArenaSession.catalog)
	var shell: Node = runtime.get_node_or_null("Shell")
	assert_not_null(shell, "the theme's stands come in with the arena")
	assert_gt(shell.get_child_count(), 0, "and setup() built something to its size")
	var walls: Node = shell.find_child("Perimeter", true, false)
	assert_not_null(walls, "including the wall that keeps the player off the edge")


func test_the_default_arena_is_playable() -> void:
	var arena: ArenaData = _default()
	assert_not_null(arena, "the arena every normal run happens in")
	assert_true(ArenaValidator.is_playable(arena, ArenaSession.catalog))


func test_the_default_arena_has_a_door_for_every_wave_id() -> void:
	# The authored waves name door_01 through door_07 and the loader numbers the
	# doors in spawn order, so anything less leaves a wave with nowhere to spawn.
	assert_gte(_default().enemy_spawns.size(), 7)


func test_the_default_arena_keeps_its_traversal() -> void:
	var runtime: ArenaRuntime = ArenaLoader.load_arena(
		_default(), _parent, ArenaSession.catalog)
	assert_not_null(runtime)
	var links: Node = runtime.get_node_or_null("NavigationLinks")
	assert_gt(links.get_child_count(), 0, "the horde can reach the walkway")
	assert_gt(runtime.get_enemy_spawns().size(), 6)


func test_props_sit_on_the_floor_tile_and_not_inside_it() -> void:
	var runtime: ArenaRuntime = ArenaLoader.load_arena(
		_default(), _parent, ArenaSession.catalog)
	var catalog: PieceCatalog = ArenaSession.catalog
	var graph: GridGraph = GridGraph.build(_default(), catalog)
	var checked: int = 0
	for child: Node in runtime.geometry_root.get_children():
		var node := child as Node3D
		if node == null or not node.name.begins_with("bounce_pad"):
			continue
		checked += 1
		var cell := Vector3i(
			int(round(node.position.x / catalog.cell_size.x)),
			int(round(node.position.y / catalog.cell_size.y)),
			int(round(node.position.z / catalog.cell_size.z)))
		var floor_y: float = float(cell.y) * catalog.cell_size.y
		assert_almost_eq(node.position.y, floor_y + graph.surface_offset(cell), 0.01,
			"a pad rests on the surface of its floor tile")
		assert_gt(node.position.y, floor_y,
			"and never at the cell floor, which is under the tile")
	assert_gt(checked, 0, "the default arena has pads to check")


func test_ground_pieces_are_still_built_from_the_cell_floor() -> void:
	var runtime: ArenaRuntime = ArenaLoader.load_arena(
		_default(), _parent, ArenaSession.catalog)
	var cell_height: float = ArenaSession.catalog.cell_size.y
	for child: Node in runtime.geometry_root.get_children():
		var node := child as Node3D
		if node == null or not node.name.begins_with("floor_1x1"):
			continue
		assert_almost_eq(fmod(node.position.y, cell_height), 0.0, 0.01,
			"floor tiles keep sitting on the cell plane")
		return
	fail_test("no floor tiles found")


func test_the_anchors_hang_within_grapple_range_of_the_floor() -> void:
	var runtime: ArenaRuntime = ArenaLoader.load_arena(
		_default(), _parent, ArenaSession.catalog)
	var found: int = 0
	for child: Node in runtime.geometry_root.get_children():
		var node := child as Node3D
		if node == null or not node.name.begins_with("grapple_anchor"):
			continue
		found += 1
		assert_gt(node.position.y, ArenaSession.catalog.cell_size.y,
			"an anchor at floor height is not worth shooting at")
		# GrappleComponent.max_range is 28m; an anchor further up than that is
		# scenery the player can never reach.
		assert_lt(node.position.y, 28.0, "%s is out of grapple range" % node.name)
	assert_gt(found, 0, "the default arena hangs anchors")
