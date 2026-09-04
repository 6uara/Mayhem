@tool
class_name ArenaGizmos
extends RefCounted
## The non-geometry things the editor has to show: the grid floor, the spawn
## markers and the placement ghost.

const GRID_COLOR := Color(1.0, 1.0, 1.0, 0.18)
const PLAYER_SPAWN_COLOR := Color("#3BE8FF")
const ENEMY_SPAWN_COLOR := Color("#FF3BC1")
const GHOST_VALID := Color(0.35, 1.0, 0.5, 0.45)
const GHOST_INVALID := Color(1.0, 0.3, 0.3, 0.45)


## A wireframe floor for the working level, so empty cells are still aimable.
static func build_grid(grid_size: Vector3i, cell_size: Vector3, level: int) -> MeshInstance3D:
	var vertices := PackedVector3Array()
	var y: float = float(level) * cell_size.y  # The cell floor, where pieces sit.
	var extent := Vector3(float(grid_size.x) * cell_size.x, 0.0, float(grid_size.z) * cell_size.z)
	var origin := Vector3(-cell_size.x * 0.5, y, -cell_size.z * 0.5)
	for x: int in grid_size.x + 1:
		var offset: float = float(x) * cell_size.x
		vertices.append(origin + Vector3(offset, 0.0, 0.0))
		vertices.append(origin + Vector3(offset, 0.0, extent.z))
	for z: int in grid_size.z + 1:
		var offset: float = float(z) * cell_size.z
		vertices.append(origin + Vector3(0.0, 0.0, offset))
		vertices.append(origin + Vector3(extent.x, 0.0, offset))

	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = "Grid"
	instance.mesh = mesh
	instance.material_override = unshaded_material(GRID_COLOR)
	return instance


static func build_spawn_marker(color: Color, cell_size: Vector3) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = minf(cell_size.x, cell_size.z) * 0.25
	mesh.height = mesh.radius * 2.0
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = unshaded_material(color)
	return instance


static func unshaded_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
