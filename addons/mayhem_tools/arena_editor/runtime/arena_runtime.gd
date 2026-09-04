@tool
class_name ArenaRuntime
extends Node3D
## An arena instanced into the world. This is the whole contact surface between
## the tools and MAYHEM: the game asks it where to put the player, where enemies
## come from, and how to path - and knows nothing about ArenaData beyond that.

## Matches the greybox arena's bake so enemy `max_auto_step` keeps its contract.
const AGENT_HEIGHT: float = 2.0
## The greybox bake asks for 0.85, but a bake ceils the radius to whole voxels of
## `NAV_CELL_SIZE`, so what that arena actually ships is 1.0. Asking for 1.0 here
## bakes the same corridor widths the enemies were tuned against and does it
## without the engine quietly rounding behind us.
const AGENT_RADIUS: float = 1.0
const AGENT_MAX_CLIMB: float = 0.5
const AGENT_MAX_SLOPE: float = 50.0
## Has to match the navigation map's cell size (project settings, 0.25) or the
## bake rasterises against a different grid than the one it is put on.
const NAV_CELL_SIZE: float = 0.25
const NAVIGATION_SOURCE_GROUP: StringName = &"navigation_source"

## The greybox arena carried the light, the environment and the stands as part of
## its scene, so an authored arena that replaces it has to bring its own or the
## match opens in a flat grey void. All of that now comes from `ArenaTheme`.
## Group the kill volume announces itself with, for anything that wants to find
## it - the editor preview draws nothing, the match uses it to end a fall.
const KILL_ZONE_GROUP: StringName = &"arena_kill_zone"

var arena: ArenaData
var catalog: PieceCatalog
var theme: ArenaTheme

var geometry_root: Node3D
var navigation_region: NavigationRegion3D
var spawn_doors_root: Node3D

var _nav_grid: NavGrid


func setup(arena_data: ArenaData, piece_catalog: PieceCatalog,
		arena_theme: ArenaTheme = null) -> void:
	arena = arena_data
	catalog = piece_catalog
	theme = arena_theme if arena_theme != null else ArenaTheme.find(arena.theme_id)
	name = "Arena_%s" % (arena.arena_name if arena.arena_name != "" else "Untitled")
	geometry_root = Node3D.new()
	geometry_root.name = "Geometry"
	add_child(geometry_root)
	navigation_region = NavigationRegion3D.new()
	navigation_region.name = "Navigation"
	navigation_region.navigation_mesh = _make_navigation_mesh()
	add_child(navigation_region)
	add_child(_make_environment())
	add_child(_make_sun())
	_build_shell()
	_build_kill_zone()
	spawn_doors_root = Node3D.new()
	spawn_doors_root.name = "SpawnDoors"
	add_child(spawn_doors_root)
	_nav_grid = NavGrid.new(GridGraph.build(arena, catalog), catalog.cell_size)


## Feet on the surface of the cell, plus a hair of clearance so nothing spawns
## intersecting the floor it is standing on.
const SPAWN_CLEARANCE: float = 0.2


func get_player_spawn() -> Vector3:
	return _standing(arena.player_spawn)


func get_enemy_spawns() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for spawn: EnemySpawnEntry in arena.enemy_spawns:
		out.append(_standing(spawn.cell))
	return out


func _standing(cell: Vector3i) -> Vector3:
	var graph: GridGraph = GridGraph.build(arena, catalog)
	return graph.standing_position(cell, catalog.cell_size) 		+ Vector3(0.0, SPAWN_CLEARANCE, 0.0)


## The deterministic grid graph. Enemies use Godot navigation; this is what the
## editor, the tests and any tool-side query path with.
func get_navigation() -> NavGrid:
	return _nav_grid


## Bakes the navmesh from the instanced geometry. Called once the pieces are in
## the tree, so it is the loader's job, not `setup`'s.
func bake_navigation() -> void:
	if navigation_region == null:
		return
	if not is_inside_tree():
		ready.connect(bake_navigation, CONNECT_ONE_SHOT)  # Baking needs the tree.
		return
	navigation_region.bake_navigation_mesh(false)


# Private

## The whole grid in metres, built or not.
func get_bounds() -> AABB:
	var size := Vector3(arena.grid_size) * catalog.cell_size
	return AABB(Vector3(-catalog.cell_size.x * 0.5, 0.0, -catalog.cell_size.z * 0.5), size)


## What was actually built, which is what the venue has to sit around. An arena
## using a quarter of a large grid should not get stands framing three quarters
## of empty space, so this is the box the shell is handed.
func get_content_bounds() -> AABB:
	if arena.placements.is_empty():
		return get_bounds()
	var lowest: Vector3i = arena.placements[0].cell
	var highest: Vector3i = lowest
	for entry: PlacementEntry in arena.placements:
		var piece: PieceDefinition = catalog.get_piece(entry.piece_id)
		if piece == null:
			continue
		for offset: Vector3i in piece.get_footprint(entry.rotation):
			lowest = lowest.min(entry.cell + offset)
			highest = highest.max(entry.cell + offset)
	var half := Vector3(catalog.cell_size.x * 0.5, 0.0, catalog.cell_size.z * 0.5)
	var low: Vector3 = catalog.cell_to_world(lowest) - half
	var high: Vector3 = catalog.cell_to_world(highest) + half 		+ Vector3(0.0, catalog.cell_size.y, 0.0)
	return AABB(low, high - low)


func _make_environment() -> WorldEnvironment:
	var node := WorldEnvironment.new()
	node.name = "WorldEnvironment"
	node.environment = theme.get_environment()
	return node


func _make_sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = theme.sun_rotation_degrees
	sun.light_energy = theme.sun_energy
	sun.light_color = theme.sun_color
	sun.shadow_enabled = true
	return sun


## The venue around the grid. A shell that exposes `setup(bounds: AABB)` is told
## how big this arena is; one that does not is instanced as authored, which is
## what a fixed backdrop wants.
func _build_shell() -> void:
	if theme.shell_scene == null:
		return
	var shell := theme.shell_scene.instantiate() as Node3D
	if shell == null:
		push_error("ArenaRuntime: the shell of theme '%s' is not a Node3D" % theme.id)
		return
	shell.name = "Shell"
	add_child(shell)
	if shell.has_method(&"setup"):
		shell.call(&"setup", get_content_bounds(), theme)


## Walking off the edge has to end. Without this the player falls out of the
## world and the run just stops being a run.
func _build_kill_zone() -> void:
	var bounds: AABB = get_bounds()
	var area := Area3D.new()
	area.name = "KillZone"
	area.add_to_group(KILL_ZONE_GROUP)
	area.monitoring = true
	var shape := BoxShape3D.new()
	var margin: float = theme.kill_plane_margin
	shape.size = Vector3(bounds.size.x + margin, 4.0, bounds.size.z + margin)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	area.add_child(collision)
	area.position = bounds.position + Vector3(
		bounds.size.x * 0.5, -theme.kill_plane_depth, bounds.size.z * 0.5)
	area.body_entered.connect(_on_kill_zone_entered)
	add_child(area)


## Kills whatever fell in, player or enemy, through the health component every
## body in MAYHEM already has. No new damage path, no special case.
func _on_kill_zone_entered(body: Node3D) -> void:
	var health: Node = body.get(&"health") as Node
	if health == null or not health.has_method(&"apply_damage"):
		return
	health.call(&"apply_damage", float(health.get(&"max_health")) * 10.0, null)


func _make_navigation_mesh() -> NavigationMesh:
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	mesh.geometry_source_group_name = NAVIGATION_SOURCE_GROUP
	mesh.cell_size = NAV_CELL_SIZE
	mesh.agent_height = AGENT_HEIGHT
	mesh.agent_radius = AGENT_RADIUS
	mesh.agent_max_climb = AGENT_MAX_CLIMB
	mesh.agent_max_slope = AGENT_MAX_SLOPE
	return mesh
