@tool
class_name ArenaLoader
extends RefCounted
## Turns arena data into a live arena. The only file in the addon the game runs.

const SPAWN_DOOR_SCENE: String = "res://scenes/arena/spawn_door.tscn"


## Instances `data` under `parent` and returns the runtime handle. Returns null
## when the arena is unplayable, so a broken file can never reach a match.
static func load_arena(data: ArenaData, parent: Node3D, catalog: PieceCatalog) -> ArenaRuntime:
	if data == null or parent == null or catalog == null:
		push_error("ArenaLoader: missing arena, parent or catalog.")
		return null
	var issues: Array[ValidationIssue] = ArenaValidator.errors(
		ArenaValidator.validate(data, catalog))
	if not issues.is_empty():
		push_error("ArenaLoader: '%s' has %d blocking issue(s); first: %s"
			% [data.arena_name, issues.size(), issues[0].message])
		return null

	var runtime := ArenaRuntime.new()
	runtime.setup(data, catalog)
	parent.add_child(runtime)
	var graph: GridGraph = GridGraph.build(data, catalog)
	_build_geometry(runtime, data, catalog, graph)
	_build_navigation_links(runtime, graph, catalog)
	_build_spawn_doors(runtime, data, catalog)
	runtime.bake_navigation()
	return runtime


# Private

static func _build_geometry(runtime: ArenaRuntime, data: ArenaData,
		catalog: PieceCatalog, graph: GridGraph) -> void:
	for entry: PlacementEntry in data.placements:
		var piece: PieceDefinition = catalog.get_piece(entry.piece_id)
		if piece == null:
			continue
		var node: Node3D = PieceMeshBuilder.build(piece, catalog)
		if node == null:
			continue
		node.name = "%s_%d_%d_%d" % [piece.id, entry.cell.x, entry.cell.y, entry.cell.z]
		# Ground pieces are built up from the cell floor; everything else sits on
		# top of whatever ground is in the cell. Without the lift a bounce pad on
		# a 0.75m floor tile spends most of its height inside it.
		node.position = catalog.cell_to_world(entry.cell) + Vector3(
			0.0, 0.0 if piece.is_ground() else graph.surface_offset(entry.cell), 0.0)
		node.rotation.y = deg_to_rad(-90.0 * entry.rotation)
		_mark_navigation_source(node)
		runtime.geometry_root.add_child(node)


## A jump link the enemies can use becomes a real NavigationLink3D, so the same
## edge the validator counted is the edge the navmesh offers. Player-only links -
## bounce pads, zip lines - are deliberately not published here: nothing in the
## horde can ride them, and a link they cannot honour sends them off a ledge.
static func _build_navigation_links(runtime: ArenaRuntime, graph: GridGraph,
		catalog: PieceCatalog) -> void:
	var parent := Node3D.new()
	parent.name = "NavigationLinks"
	runtime.add_child(parent)
	for pair: Array in graph.shared_links():
		var link := NavigationLink3D.new()
		link.start_position = graph.standing_position(pair[0], catalog.cell_size)
		link.end_position = graph.standing_position(pair[1], catalog.cell_size)
		link.bidirectional = false  # add_link() already emitted both directions.
		parent.add_child(link)


static func _mark_navigation_source(node: Node3D) -> void:
	node.add_to_group(ArenaRuntime.NAVIGATION_SOURCE_GROUP)


static func _build_spawn_doors(runtime: ArenaRuntime, data: ArenaData,
		catalog: PieceCatalog) -> void:
	var door_scene := load(SPAWN_DOOR_SCENE) as PackedScene
	for index: int in data.enemy_spawns.size():
		var spawn: EnemySpawnEntry = data.enemy_spawns[index]
		var position: Vector3 = catalog.cell_to_world(spawn.cell) \
			+ Vector3(0.0, catalog.cell_size.y * 0.5, 0.0)
		var door: Node3D = door_scene.instantiate() as Node3D if door_scene != null else Node3D.new()
		door.name = "Door%02d" % (index + 1)
		door.position = position
		if door.get(&"door_id") != null:
			door.set(&"door_id", StringName("door_%02d" % (index + 1)))
		runtime.spawn_doors_root.add_child(door)
