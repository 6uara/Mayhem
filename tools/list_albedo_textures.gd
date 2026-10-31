extends SceneTree
## Lista las texturas de color (albedo) de todos los modelos de assets/models,
## para que tools/blender/flatten_textures.py les haga su version toon.
##
##     godot --headless --path . -s tools/list_albedo_textures.gd -- salida.json
##
## Desde Godot y no desde Blender porque lo que importa es que textura termina
## siendo el albedo de un material *en el juego*: los `.jpg` que Godot extrae de
## un `.glb` se llaman `<modelo>_Image_N.jpg`, y solo el importador sabe cual de
## ellos es color, cual normal y cual rugosidad. Se saltean las texturas
## embebidas (sin archivo propio), que no tienen al lado donde poner la variante.
##
## Escribe un JSON con una lista de rutas absolutas. No toca nada versionado.

const MODELS_DIR: String = "res://assets/models"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var output: String = args[0] if not args.is_empty() else "user://albedo_textures.json"
	var found: Dictionary = {}
	for path: String in _find_models(MODELS_DIR):
		# Las fuentes de Meshy llegan con importer="skip": solo las lee Blender.
		# ResourceLoader.exists() dice que si igual, asi que se mira el .import.
		if _is_skipped(path):
			continue
		var scene: PackedScene = load(path) as PackedScene
		if scene == null:
			continue
		var root_node: Node = scene.instantiate()
		_collect(root_node, found)
		root_node.free()
	var paths: Array = []
	for res_path: String in found.keys():
		paths.append(ProjectSettings.globalize_path(res_path))
	paths.sort()
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(paths, "  "))
	file.close()
	print("albedo textures: %d -> %s" % [paths.size(), ProjectSettings.globalize_path(output)])
	quit()


func _find_models(dir_path: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	for sub: String in dir.get_directories():
		result.append_array(_find_models(dir_path.path_join(sub)))
	for file_name: String in dir.get_files():
		if file_name.get_extension() == "glb":
			result.append(dir_path.path_join(file_name))
	return result


func _collect(node: Node, found: Dictionary) -> void:
	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		for i: int in mesh_instance.mesh.get_surface_count():
			_add(mesh_instance.mesh.surface_get_material(i), found)
		for i: int in mesh_instance.get_surface_override_material_count():
			_add(mesh_instance.get_surface_override_material(i), found)
	for child: Node in node.get_children():
		_collect(child, found)


func _add(material: Material, found: Dictionary) -> void:
	var base := material as BaseMaterial3D
	if base == null or base.albedo_texture == null:
		return
	var path: String = base.albedo_texture.resource_path
	# Embebida en el .glb: "res://...glb::Texture2D_xxx". Sin archivo propio.
	if path.is_empty() or path.contains("::") or path.get_basename().ends_with("_toon"):
		return
	found[path] = true


func _is_skipped(path: String) -> bool:
	var config := ConfigFile.new()
	if config.load(path + ".import") != OK:
		return true
	return String(config.get_value("remap", "importer", "")) == "skip"
