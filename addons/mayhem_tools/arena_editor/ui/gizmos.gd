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
## El contorno de lo que un click de borrar se lleva. Rojo, como el rechazo, y
## sin relleno: es un marco alrededor de la pieza, no una pieza mas.
const ERASE_HIGHLIGHT := Color(1.0, 0.35, 0.3, 0.9)
## Lo que se levanto con la herramienta de mover y todavia no se solto.
const MOVE_HIGHLIGHT := Color(1.0, 0.85, 0.3, 0.9)
## El recorrido de una plataforma movil. Cyan, el color de lo que el jugador usa
## para moverse, igual que la plataforma en el juego.
const TRAVEL_PATH_COLOR := Color(0.3, 0.95, 1.0, 0.9)


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


## Marco de alambre de una celda, apoyado en su piso. Sirve para decir "esto es
## lo que estas por tocar" sin taparlo con geometria opaca.
static func build_cell_outline(color: Color, cell_size: Vector3) -> MeshInstance3D:
	var half := Vector3(cell_size.x * 0.5, 0.0, cell_size.z * 0.5)
	var low := Vector3(-half.x, 0.0, -half.z)
	var high := Vector3(half.x, cell_size.y, half.z)
	var corners: Array[Vector3] = [
		Vector3(low.x, low.y, low.z), Vector3(high.x, low.y, low.z),
		Vector3(high.x, low.y, high.z), Vector3(low.x, low.y, high.z),
		Vector3(low.x, high.y, low.z), Vector3(high.x, high.y, low.z),
		Vector3(high.x, high.y, high.z), Vector3(low.x, high.y, high.z),
	]
	var edges: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 0),
		Vector2i(4, 5), Vector2i(5, 6), Vector2i(6, 7), Vector2i(7, 4),
		Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7),
	]
	var vertices := PackedVector3Array()
	for edge: Vector2i in edges:
		vertices.append(corners[edge.x])
		vertices.append(corners[edge.y])

	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = "CellOutline"
	instance.mesh = mesh
	var material: StandardMaterial3D = unshaded_material(color)
	# Sin test de profundidad: el marco de una pieza que esta detras de otra
	# igual tiene que verse, o el resaltado miente sobre que se va a borrar.
	material.no_depth_test = true
	instance.material_override = material
	return instance


## De donde a donde va una pieza movil: una linea por el medio del recorrido,
## una flecha en cada celda que cruza, y la silueta de la pieza en la otra punta.
## `from` y `to` en el espacio del nodo que la contenga, a la altura de la cara
## que se pisa. Se dibuja por encima de todo: un recorrido tapado por la pieza
## que el jugador esta por poner no le dice nada.
static func build_travel_path(from: Vector3, to: Vector3, footprint: Vector2,
		color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "TravelPath"
	var vertices := PackedVector3Array()
	vertices.append(from)
	vertices.append(to)
	var span: Vector3 = to - from
	var direction: Vector3 = span.normalized() if span.length() > 0.001 else Vector3.FORWARD
	var side: Vector3 = direction.cross(Vector3.UP).normalized()
	if side.length() < 0.001:
		side = Vector3.RIGHT
	var head: float = minf(footprint.x, footprint.y) * 0.18
	# Una flecha por metro y medio de camino, no por celda: la de la punta sola
	# no alcanza para leer el sentido desde lejos.
	var arrows: int = maxi(int(span.length() / 1.5), 1)
	for index: int in range(1, arrows + 1):
		var tip: Vector3 = from + span * (float(index) / float(arrows))
		vertices.append(tip)
		vertices.append(tip - direction * head + side * head)
		vertices.append(tip)
		vertices.append(tip - direction * head - side * head)
	# La silueta de la pieza en la punta de llegada.
	var half := Vector3(footprint.x * 0.5, 0.0, footprint.y * 0.5)
	var corners: Array[Vector3] = [
		to + Vector3(-half.x, 0.0, -half.z), to + Vector3(half.x, 0.0, -half.z),
		to + Vector3(half.x, 0.0, half.z), to + Vector3(-half.x, 0.0, half.z),
	]
	for index: int in 4:
		vertices.append(corners[index])
		vertices.append(corners[(index + 1) % 4])

	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var lines := MeshInstance3D.new()
	lines.name = "Lines"
	lines.mesh = mesh
	var line_material: StandardMaterial3D = unshaded_material(color)
	line_material.no_depth_test = true
	lines.material_override = line_material
	root.add_child(lines)

	var slab := MeshInstance3D.new()
	slab.name = "Arrival"
	var plane := PlaneMesh.new()
	plane.size = footprint
	slab.mesh = plane
	slab.position = to + Vector3(0.0, 0.02, 0.0)
	slab.material_override = unshaded_material(Color(color, color.a * 0.25))
	root.add_child(slab)
	return root


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
