extends SceneTree
## Bakes an imported model's mesh down into a bare .res ArrayMesh for EnemyData.mesh.
##
## EnemyData.mesh is typed as `Mesh`, not `PackedScene` (unlike WeaponData.viewmodel),
## so the .fbx/.glb import's root transform (Z-up->Y-up conversion, source-file scale)
## has to be baked in by hand rather than carried along by node hierarchy. This tool
## replaces the one-off scratch SceneTree script that produced the first bake
## (assets/models/meshes/spiderbot.res) - see docs/Mayhem/11 Asset Pipeline.md and
## docs/Mayhem/12 Known Issues and Gaps.md. Re-run it for every new enemy model rather
## than repeating the manual process; the next one is at least the fourth.
##
## Process per surface: instantiate the source scene, find the MeshInstance3D, compose
## its local transform down from the scene root, SurfaceTool.append_from(mesh, surface,
## transform) into a new ArrayMesh. The result is then recentred on its own AABB and
## rescaled so its tallest axis matches --height, matching how the box/capsule
## placeholders were authored: pivot at the shape's own center, not the source rig's
## origin (which for at least one imported model was nowhere near the body).
##
##     godot --headless --path . -s tools/bake_enemy_meshes.gd -- \
##         res://assets/models/enemies/<Name>/<file>.fbx \
##         res://assets/models/meshes/<name>.res \
##         --height=1.8
##
## --height matches the target EnemyData.collision_height so the baked mesh lines up
## with its capsule collider out of the box; omit it to skip rescaling (source scale
## kept as-is).
##
## Implemented against MainLoop callbacks rather than `await`, because awaiting frames
## from a SceneTree script's _init() hangs - the loop is not running yet (see
## bake_navmesh.gd).

## Frames to let the imported scene settle before its mesh is read back.
const SETTLE_FRAMES: int = 2

var _frames: int = 0
var _source_path: String = ""
var _output_path: String = ""
var _target_height: float = 0.0
var _instance: Node3D


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("bake_enemy_meshes: usage: <source.fbx/glb> <output.res> [--height=H]")
		quit(1)
		return
	_source_path = args[0]
	_output_path = args[1]
	for i: int in range(2, args.size()):
		var arg: String = args[i]
		if arg.begins_with("--height="):
			_target_height = arg.trim_prefix("--height=").to_float()

	if not ResourceLoader.exists(_source_path):
		push_error("bake_enemy_meshes: no such source %s" % _source_path)
		quit(1)
		return

	var packed: PackedScene = load(_source_path)
	if packed == null:
		push_error("bake_enemy_meshes: failed to load %s" % _source_path)
		quit(1)
		return

	_instance = packed.instantiate()
	root.add_child(_instance)


func _process(_delta: float) -> bool:
	if _instance == null:
		return true
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false

	var mesh_instance: MeshInstance3D = _find_mesh_instance(_instance)
	if mesh_instance == null:
		push_error("bake_enemy_meshes: no MeshInstance3D found under %s" % _source_path)
		quit(1)
		return true

	var source_mesh: Mesh = mesh_instance.mesh
	if source_mesh == null or source_mesh.get_surface_count() == 0:
		push_error("bake_enemy_meshes: %s has no surfaces" % _source_path)
		quit(1)
		return true

	var local_transform: Transform3D = _compose_transform(mesh_instance, _instance)
	var baked: ArrayMesh = ArrayMesh.new()
	for surface: int in source_mesh.get_surface_count():
		var surface_tool := SurfaceTool.new()
		surface_tool.append_from(source_mesh, surface, local_transform)
		surface_tool.commit(baked)
		var material: Material = source_mesh.surface_get_material(surface)
		if material != null:
			baked.surface_set_material(surface, material)

	_recenter_and_rescale(baked)

	var error: int = ResourceSaver.save(baked, _output_path)
	if error != OK:
		push_error("bake_enemy_meshes: failed to save %s (%d)" % [_output_path, error])
		quit(1)
		return true

	print("Baked %s -> %s (%d surface(s))" % [
		_source_path, _output_path, baked.get_surface_count()])
	quit()
	return true


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = node as MeshInstance3D
	if mesh_instance != null:
		return mesh_instance
	for child: Node in node.get_children():
		var found: MeshInstance3D = _find_mesh_instance(child)
		if found != null:
			return found
	return null


## Transform from the MeshInstance3D's local space down to the scene root, so the
## baked geometry lands the same way the import hierarchy would have placed it.
func _compose_transform(mesh_instance: MeshInstance3D, scene_root: Node3D) -> Transform3D:
	var result: Transform3D = Transform3D.IDENTITY
	var node: Node3D = mesh_instance
	while node != null and node != scene_root:
		result = node.transform * result
		node = node.get_parent() as Node3D
	return result


## Recenters the mesh on its own AABB (pivot at the shape's center, not the source
## rig's origin) and, if --height was given, rescales so its tallest axis matches it.
## Rebuilds into a fresh ArrayMesh rather than mutating surfaces in place - removing
## and re-adding a surface by index while iterating shifts every later index out from
## under the loop.
func _recenter_and_rescale(mesh: ArrayMesh) -> void:
	var aabb: AABB = mesh.get_aabb()
	var center: Vector3 = aabb.get_center()
	var scale: float = 1.0
	if _target_height > 0.0 and aabb.size.y > 0.0:
		scale = _target_height / aabb.size.y

	var surface_count: int = mesh.get_surface_count()
	var rebuilt: Array[Dictionary] = []
	for surface: int in surface_count:
		var arrays: Array = mesh.surface_get_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i: int in positions.size():
			positions[i] = (positions[i] - center) * scale
		arrays[Mesh.ARRAY_VERTEX] = positions
		rebuilt.push_back({
			"arrays": arrays,
			"material": mesh.surface_get_material(surface),
			"name": mesh.surface_get_name(surface),
		})

	for surface: int in surface_count:
		mesh.surface_remove(0)

	for entry: Dictionary in rebuilt:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, entry["arrays"])
		var new_index: int = mesh.get_surface_count() - 1
		if entry["material"] != null:
			mesh.surface_set_material(new_index, entry["material"])
		if not String(entry["name"]).is_empty():
			mesh.surface_set_name(new_index, entry["name"])
