extends Node
## El estilo visual del juego, elegido en opciones (`video/visual_style`).
##
## - **Estandar.** Los modelos como llegaron.
## - **Claridad** (el default). Pensado para que un jugador nuevo sepa que mirar.
##   Una sola regla: **si tiene borde, importa**, y el color dice que hace. Los
##   enemigos ya tenian el suyo; ahora lo tienen tambien lo que se usa (anclas,
##   pads, plataformas), lo que se levanta (municion, gadgets) y las
##   puertas de donde salen enemigos (SemanticOutline). El mapa no lleva borde, y
##   el fondo -cuenco, publico, ciudad, pared de energia- retrocede: menos color y
##   menos brillo (background_recede.gdshaderinc). Antes el fondo era lo mas
##   fuerte de la pantalla, y en el cyan que la ley reserva para "lo tuyo".
## - **Toon.** Luz en bandas, texturas aplanadas (`_toon.png`, ver
##   tools/blender/flatten_textures.py) y tinta oscura en siluetas y quiebres.
##   Queda como opcion: sobre una arena de noche la tinta no se lee.
##
## Se probo tambien un "neon de transmision": un filo de luz en todas las
## siluetas del mapa y una pasada de camara de TV. Con todo delineado nada se
## destacaba, que es lo contrario de lo que se buscaba. Esta en el historial de
## la rama `feat/visual-style`.
##
## Claridad no toca materiales: cada objeto ya pidio su borde y el fondo ya tiene
## su retroceso, y el estilo cuelga los bordes (SemanticOutline.set_enabled) y
## sube dos globales de shader (`semantic_outline_px`, `background_dim`). El
## toon si toca materiales: un autoload que mira
## `node_added`, porque los modelos de Meshy, las piezas de la arena, los
## enemigos del pool y el viewmodel arman sus materiales en lugares distintos.
## Los materiales de un `.glb` son compartidos: convertir uno convierte a todos
## los que lo usan, y por eso se guarda el valor original para volver.

enum Style { STANDARD, CLARITY, TOON }

const EDGE_SHADER: Shader = preload("res://assets/shaders/edge_lines.gdshader")
const EDGE_NODE_NAME: String = "StyleEdges"
## Lo que un material tenia antes de convertirse, para poder volver.
const META_ORIGINAL: StringName = &"toon_original"
## Lo que se le agrega al nombre de una textura para su version aplanada.
const TOON_TEXTURE_SUFFIX: String = "_toon.png"

var style: Style = Style.STANDARD

## Materiales convertidos al toon. Referencia fuerte a proposito: son pocos (uno
## por superficie de modelo, compartidos) y hace falta poder recorrerlos al volver.
var _converted: Array[BaseMaterial3D] = []
var _edges: Array[MeshInstance3D] = []
## Ruta de la variante aplanada -> la textura, o null si no existe. Tambien los
## ausentes: sin eso, cada material sin variante vuelve a preguntarle al disco.
var _toon_textures: Dictionary = {}
## Nodos que entraron este frame. Se procesan al final del frame y no en
## `node_added`: el codigo que arma una malla por script suele asignar la malla o
## el material despues del `add_child`.
var _pending: Array[Node] = []
var _flush_queued: bool = false
var _ink_material: ShaderMaterial
## La tinta del arma en primera persona, mas permisiva. Ver _ready().
var _viewmodel_ink_material: ShaderMaterial


func _ready() -> void:
	_ink_material = _edge_material(Tokens.TOON_LINE, Tokens.TOON_LINE_PX)
	# El arma y las manos ocupan media pantalla a centimetros de la camara: con el
	# umbral del mundo, cada pliegue del modelo de Meshy se volvia una raya y el
	# arma quedaba rayada como un grabado. Aca solo los quiebres fuertes.
	_viewmodel_ink_material = _ink_material.duplicate() as ShaderMaterial
	_viewmodel_ink_material.set_shader_parameter(&"normal_threshold", 0.75)
	_viewmodel_ink_material.set_shader_parameter(&"depth_threshold", 0.15)
	get_tree().node_added.connect(_on_node_added)
	EventBus.settings_applied.connect(refresh)
	refresh()


# Public API

## Lee las opciones: el estilo y el ancho de la tinta. Lo llama `settings_applied`.
func refresh() -> void:
	var width: float = get_line_px()
	_ink_material.set_shader_parameter(&"line_px", width)
	_viewmodel_ink_material.set_shader_parameter(&"line_px", width)
	set_style(clampi(int(SettingsManager.get_value("video/visual_style")),
		Style.STANDARD, Style.TOON) as Style)


## El ancho de la tinta tal como llega al shader: el elegido, dentro de los
## limites de Tokens.
func get_line_px() -> float:
	return clampf(float(SettingsManager.get_value("video/toon_line_px")),
		Tokens.TOON_LINE_PX_MIN, Tokens.TOON_LINE_PX_MAX)


## El ancho del borde de "esto importa" (global `semantic_outline_px`): solo en
## Claridad.
func get_semantic_outline_px() -> float:
	return Tokens.SEMANTIC_OUTLINE_PX if style == Style.CLARITY else 0.0


## Cuanto retrocede el fondo (global `background_dim`): solo en Claridad.
func get_background_dim() -> float:
	return Tokens.BACKGROUND_DIM if style == Style.CLARITY else 0.0


func set_style(value: Style) -> void:
	RenderingServer.global_shader_parameter_set(&"semantic_outline_px",
		Tokens.SEMANTIC_OUTLINE_PX if value == Style.CLARITY else 0.0)
	RenderingServer.global_shader_parameter_set(&"background_dim",
		Tokens.BACKGROUND_DIM if value == Style.CLARITY else 0.0)
	if (value == Style.CLARITY) != SemanticOutline.enabled:
		SemanticOutline.set_enabled(value == Style.CLARITY,
			get_tree() if is_inside_tree() else null)
	if value == style:
		return
	_clear()
	style = value
	if style == Style.TOON and is_inside_tree():
		_visit(get_tree().root)


## Convierte un material al toon. Devuelve true si lo convirtio (o ya lo estaba).
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
		"albedo": base.albedo_texture,
	})
	var flat: Texture2D = toon_texture_for(base.albedo_texture)
	if flat != null:
		base.albedo_texture = flat
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
	base.albedo_texture = original["albedo"] as Texture2D
	base.remove_meta(META_ORIGINAL)


## La version aplanada de una textura de color: `<nombre>_toon.png` al lado de la
## original. Null si no hay (una textura embebida en el .glb, o un modelo que
## todavia no se aplano): el material queda con la suya y solo cambia la luz.
func toon_texture_for(texture: Texture2D) -> Texture2D:
	if texture == null or texture.resource_path.is_empty() \
			or texture.resource_path.contains("::"):
		return null
	var path: String = texture.resource_path.get_basename() + TOON_TEXTURE_SUFFIX
	if not _toon_textures.has(path):
		_toon_textures[path] = load(path) as Texture2D \
			if ResourceLoader.exists(path) else null
	return _toon_textures[path]


## La tinta de una camara (toon), o null si no tiene.
func get_edges(camera: Camera3D) -> MeshInstance3D:
	return camera.get_node_or_null(EDGE_NODE_NAME) as MeshInstance3D


# Private

func _edge_material(color: Color, width: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = EDGE_SHADER
	material.set_shader_parameter(&"line_color", color)
	material.set_shader_parameter(&"line_px", width)
	# Antes que cualquier otro transparente: un fogonazo o un numero de daño se
	# dibujan encima de la linea, no debajo.
	material.render_priority = Material.RENDER_PRIORITY_MIN
	return material


func _on_node_added(node: Node) -> void:
	if style != Style.TOON:
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
		if is_instance_valid(node) and style == Style.TOON:
			_process_node(node)


func _visit(node: Node) -> void:
	_process_node(node)
	for child: Node in node.get_children():
		_visit(child)


func _process_node(node: Node) -> void:
	var camera := node as Camera3D
	if camera != null:
		_add_edges(camera)
		return
	var geometry := node as GeometryInstance3D
	if geometry == null or geometry.name == EDGE_NODE_NAME:
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
func _add_edges(camera: Camera3D) -> void:
	if get_edges(camera) != null:
		return
	var quad := MeshInstance3D.new()
	quad.name = EDGE_NODE_NAME
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	quad.mesh = mesh
	quad.material_override = _viewmodel_ink_material \
		if camera.get_viewport() is SubViewport else _ink_material
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# El vertex lo pone sobre toda la pantalla; sin esto el culling lo descarta
	# cuando su caja de 2 m queda detras de la camara.
	quad.extra_cull_margin = 16384.0
	quad.layers = _first_layer(camera.cull_mask)
	camera.add_child(quad)
	_edges.append(quad)


func _first_layer(mask: int) -> int:
	for bit: int in 20:
		if mask & (1 << bit):
			return 1 << bit
	return 1


## Deshace el toon: materiales y tinta.
func _clear() -> void:
	for material: BaseMaterial3D in _converted:
		restore_material(material)
	_converted.clear()
	for quad: MeshInstance3D in _edges:
		if is_instance_valid(quad):
			# free() y no queue_free(): al volver al toon la camara recibe su quad
			# nuevo en el mismo frame, y el viejo con el mismo nombre todavia
			# colgado haria que get_edges() crea que ya tiene.
			quad.get_parent().remove_child(quad)
			quad.free()
	_edges.clear()
	_pending.clear()
