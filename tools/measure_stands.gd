@tool
extends SceneTree
## Mide las secciones de grada y donde cae el publico sobre ellas.
##
##   godot --headless --script tools/measure_stands.gd
##
## Existe porque el publico se sembraba sobre numeros deducidos del bounding box
## de la seccion, y un bounding box no dice donde esta la superficie sentable:
## una grada solida y una rampa del mismo alto miden igual y no se sientan igual.

const STAND: String = "res://assets/models/arena/SingleStand.blend"
const CORNER: String = "res://assets/models/arena/CornerStand.blend"


func _initialize() -> void:
	for path: String in [STAND, CORNER]:
		_report(path)
	quit()


func _report(path: String) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		print("no se pudo cargar ", path)
		return
	var node := scene.instantiate() as Node3D
	var meshes: Array[MeshInstance3D] = []
	_collect(node, meshes)
	var bounds := AABB()
	var first: bool = true
	var triangles: int = 0
	for mesh: MeshInstance3D in meshes:
		var box: AABB = mesh.transform * mesh.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
		for surface: int in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangles += (indices.size() if indices.size() > 0
				else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3

	print("\n== ", path.get_file())
	print("  mallas:     ", meshes.size(), "   triangulos: ", triangles)
	print("  origen:     ", bounds.position)
	print("  tamano:     ", bounds.size)
	print("  (largo x, alto y, fondo z)")
	_rake(meshes, bounds)
	node.free()


## Muestrea la altura de la superficie a lo largo del fondo de la seccion. Es lo
## que dice si la grada es una rampa donde sentar gente o un bloque con la cara
## de arriba plana.
func _rake(meshes: Array[MeshInstance3D], bounds: AABB) -> void:
	var samples: int = 8
	var tops: PackedFloat32Array = PackedFloat32Array()
	tops.resize(samples)
	tops.fill(-INF)
	for mesh: MeshInstance3D in meshes:
		for surface: int in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array:
				var world: Vector3 = mesh.transform * vertex
				var t: float = (world.z - bounds.position.z) / maxf(bounds.size.z, 0.001)
				var slot: int = clampi(int(t * float(samples)), 0, samples - 1)
				tops[slot] = maxf(tops[slot], world.y - bounds.position.y)
	var line: String = "  perfil y:  "
	for value: float in tops:
		line += "%6.2f" % value
	print(line)
	print("             fondo 0%%  ->  100%%")


func _collect(node: Node, found: Array[MeshInstance3D]) -> void:
	var mesh := node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		found.append(mesh)
	for child: Node in node.get_children():
		_collect(child, found)
