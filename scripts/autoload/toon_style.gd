extends Node
## El estilo toon, prendido o apagado desde opciones (`video/toon_style`).
##
## Dos piezas, las dos sin tocar un asset:
##
## - **Luz en bandas.** Cada `BaseMaterial3D` con sombreado que entra al arbol
##   pasa a `DIFFUSE_TOON`, sin brillo especular ni metal, y pierde el mapa de
##   normales, que con la luz en bandas solo agrega ruido. Es el mismo shader
##   con otra funcion de luz: no cuesta un ciclo. Los `ShaderMaterial` (pisos animados, charcos,
##   paredes de energia) y lo `unshaded` (VFX, contornos) no se tocan: ya tienen
##   su propio look.
## - **Linea de tinta.** Un quad pegado a cada `Camera3D` con
##   `toon_outline.gdshader`: un pase de pantalla, no un casco por malla. Ver el
##   shader para el por que.
##
## Por que un autoload que mira `node_added` y no un cambio en cada escena: los
## modelos de Meshy, las piezas de la arena, los enemigos del pool y el viewmodel
## arman sus materiales en lugares distintos, y el prototipo tiene que poder
## compararse prendido y apagado sin reimportar nada. Si el look se queda, lo que
## hoy se hace aca al cargar puede pasar a los scripts de Blender.
##
## Los materiales de un `.glb` son recursos compartidos: convertir uno convierte
## a todos los que lo usan, y por eso se guarda el valor original para volver.

const OUTLINE_SHADER: Shader = preload("res://assets/shaders/toon_outline.gdshader")
const OUTLINE_NODE_NAME: String = "ToonOutline"
## Lo que un material tenia antes de convertirse, para poder volver.
const META_ORIGINAL: StringName = &"toon_original"

var enabled: bool = false

## Materiales convertidos. Referencia fuerte a proposito: son pocos (uno por
## superficie de modelo, compartidos) y hace falta poder recorrerlos al apagar.
var _converted: Array[BaseMaterial3D] = []
var _outlines: Array[MeshInstance3D] = []
## Nodos que entraron este frame. Se procesan al final del frame y no en
## `node_added`: el codigo que arma una malla por script suele asignar la malla o
## el material despues del `add_child`.
var _pending: Array[Node] = []
var _flush_queued: bool = false
var _outline_material: ShaderMaterial
## La del arma en primera persona, mas permisiva. Ver _ready().
var _viewmodel_outline_material: ShaderMaterial


func _ready() -> void:
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = OUTLINE_SHADER
	_outline_material.set_shader_parameter(&"line_color", Tokens.TOON_LINE)
	_outline_material.set_shader_parameter(&"line_px", Tokens.TOON_LINE_PX)
	# Antes que cualquier otro transparente: un fogonazo o un numero de daño se
	# dibujan encima de la linea, no debajo.
	_outline_material.render_priority = Material.RENDER_PRIORITY_MIN
	# El arma y las manos ocupan media pantalla a centimetros de la camara: con el
	# umbral del mundo, cada pliegue del modelo de Meshy se volvia una raya y el
	# arma quedaba rayada como un grabado. Aca solo los quiebres fuertes.
	_viewmodel_outline_material = _outline_material.duplicate() as ShaderMaterial
	_viewmodel_outline_material.set_shader_parameter(&"normal_threshold", 0.75)
	_viewmodel_outline_material.set_shader_parameter(&"depth_threshold", 0.15)
	get_tree().node_added.connect(_on_node_added)
	EventBus.settings_applied.connect(refresh)
	refresh()


# Public API

## Lee la opcion y prende o apaga. Lo llama `settings_applied`.
func refresh() -> void:
	set_enabled(bool(SettingsManager.get_value("video/toon_style")))


func set_enabled(value: bool) -> void:
	if value == enabled:
		return
	enabled = value
	if not is_inside_tree():
		return
	if enabled:
		_visit(get_tree().root)
	else:
		_restore_all()


## Convierte un material. Devuelve true si lo convirtio (o ya lo estaba).
## Publico para las pruebas.
func convert_material(material: Material) -> bool:
	var base := material as BaseMaterial3D
	if base == null or base.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL:
		return false
	if base.has_meta(META_ORIGINAL):
		return true
	base.set_meta(META_ORIGINAL, {
		"diffuse": base.diffuse_mode,
		"specular": base.specular_mode,
		"normal": base.normal_enabled,
		"metallic": base.metallic,
	})
	base.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	# Sin brillo directo y sin metal: con SPECULAR_TOON una rampa de frente al sol
	# se volvia un manchon blanco plano, y el reflejo de un metal es justo el
	# detalle realista que el toon saca.
	base.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	base.metallic = 0.0
	base.normal_enabled = false
	_converted.append(base)
	return true


func restore_material(base: BaseMaterial3D) -> void:
	if base == null or not base.has_meta(META_ORIGINAL):
		return
	var original: Dictionary = base.get_meta(META_ORIGINAL)
	base.diffuse_mode = int(original["diffuse"]) as BaseMaterial3D.DiffuseMode
	base.specular_mode = int(original["specular"]) as BaseMaterial3D.SpecularMode
	base.normal_enabled = bool(original["normal"])
	base.metallic = float(original["metallic"])
	base.remove_meta(META_ORIGINAL)


## La linea de tinta de una camara, o null si no tiene.
func get_outline(camera: Camera3D) -> MeshInstance3D:
	return camera.get_node_or_null(OUTLINE_NODE_NAME) as MeshInstance3D


# Private

func _on_node_added(node: Node) -> void:
	if not enabled:
		return
	if not (node is GeometryInstance3D or node is Camera3D):
		return
	_pending.append(node)
	if not _flush_queued:
		_flush_queued = true
		_flush.call_deferred()


func _flush() -> void:
	_flush_queued = false
	var nodes: Array[Node] = _pending
	_pending = []
	for node: Node in nodes:
		if is_instance_valid(node) and enabled:
			_process_node(node)


func _visit(node: Node) -> void:
	_process_node(node)
	for child: Node in node.get_children():
		_visit(child)


func _process_node(node: Node) -> void:
	var camera := node as Camera3D
	if camera != null:
		_add_outline(camera)
		return
	var geometry := node as GeometryInstance3D
	if geometry == null or geometry.name == OUTLINE_NODE_NAME:
		return
	if geometry.material_override != null:
		convert_material(geometry.material_override)
	var mesh: Mesh = null
	var mesh_instance := geometry as MeshInstance3D
	if mesh_instance != null:
		mesh = mesh_instance.mesh
		for i: int in mesh_instance.get_surface_override_material_count():
			var override: Material = mesh_instance.get_surface_override_material(i)
			if override != null:
				convert_material(override)
	var multi := geometry as MultiMeshInstance3D
	if multi != null and multi.multimesh != null:
		mesh = multi.multimesh.mesh
	if mesh != null:
		for i: int in mesh.get_surface_count():
			var surface: Material = mesh.surface_get_material(i)
			if surface != null:
				convert_material(surface)


## Un quad que cubre la pantalla, hijo de la camara para que viva y muera con
## ella. En la capa que la camara ve: el viewmodel tiene la suya en otro mundo.
func _add_outline(camera: Camera3D) -> void:
	if get_outline(camera) != null:
		return
	var quad := MeshInstance3D.new()
	quad.name = OUTLINE_NODE_NAME
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	quad.mesh = mesh
	quad.material_override = _outline_material if not camera.get_viewport() is SubViewport \
		else _viewmodel_outline_material
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# El vertex lo pone sobre toda la pantalla; sin esto el culling lo descarta
	# cuando su caja de 2 m queda detras de la camara.
	quad.extra_cull_margin = 16384.0
	quad.layers = _first_layer(camera.cull_mask)
	camera.add_child(quad)
	_outlines.append(quad)


func _first_layer(mask: int) -> int:
	for bit: int in 20:
		if mask & (1 << bit):
			return 1 << bit
	return 1


func _restore_all() -> void:
	for material: BaseMaterial3D in _converted:
		restore_material(material)
	_converted.clear()
	for quad: MeshInstance3D in _outlines:
		if is_instance_valid(quad):
			quad.queue_free()
	_outlines.clear()
	_pending.clear()
