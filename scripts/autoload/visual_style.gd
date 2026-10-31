extends Node
## El estilo visual del juego, elegido en opciones (`video/visual_style`).
##
## - **Estandar.** Los modelos como llegaron; nada de lo de abajo.
## - **Neon de transmision** (el default). Un filo de luz en las siluetas del
##   mundo (`edge_lines.gdshader`, solo el lado del objeto, por encima de 1 para
##   que lo agarre el glow) y la pasada de camara de TV (`broadcast_post.gdshader`:
##   color, barrido, viñeta y corrimiento en los bordes que crece con un golpe o
##   con la velocidad). El arma y las manos quedan como estan: ocupan media
##   pantalla, y todo lo que se les hizo en el toon se notaba demasiado.
## - **Toon.** Luz en bandas, texturas aplanadas (`_toon.png`, ver
##   tools/blender/flatten_textures.py) y tinta oscura en siluetas y quiebres.
##   Queda como opcion: sobre una arena de noche la tinta no tiene contra que
##   leerse.
##
## Por que un autoload que mira `node_added` y no un cambio en cada escena: los
## modelos de Meshy, las piezas de la arena, los enemigos del pool y el viewmodel
## arman sus materiales en lugares distintos, y los estilos tienen que poder
## compararse en vivo sin reimportar nada.
##
## Los materiales de un `.glb` son recursos compartidos: convertir uno convierte
## a todos los que lo usan, y por eso se guarda el valor original para volver.

enum Style { STANDARD, NEON, TOON }

const EDGE_SHADER: Shader = preload("res://assets/shaders/edge_lines.gdshader")
const BROADCAST_SHADER: Shader = preload("res://assets/shaders/broadcast_post.gdshader")
const EDGE_NODE_NAME: String = "StyleEdges"
## Lo que un material tenia antes de convertirse, para poder volver.
const META_ORIGINAL: StringName = &"toon_original"
## Lo que se le agrega al nombre de una textura para su version aplanada.
const TOON_TEXTURE_SUFFIX: String = "_toon.png"
## Daño que llena el pulso de la pasada de transmision de un saque.
const PULSE_FULL_DAMAGE: float = 35.0
## Cuanto tarda en irse el pulso de un golpe, por segundo.
const PULSE_DECAY: float = 1.6
## Entre estas velocidades (m/s) la velocidad suma pulso: de correr rapido a la
## caida o el gancho. Por debajo, caminar no mueve la imagen.
const SPEED_PULSE_FROM: float = 14.0
const SPEED_PULSE_TO: float = 30.0
const SPEED_PULSE_MAX: float = 0.45

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
var _neon_material: ShaderMaterial
var _broadcast_layer: CanvasLayer
var _broadcast_material: ShaderMaterial
var _hit_pulse: float = 0.0


func _ready() -> void:
	_ink_material = _edge_material(Tokens.TOON_LINE, 1.0, Tokens.TOON_LINE_PX)
	# El arma y las manos ocupan media pantalla a centimetros de la camara: con el
	# umbral del mundo, cada pliegue del modelo de Meshy se volvia una raya y el
	# arma quedaba rayada como un grabado. Aca solo los quiebres fuertes.
	_viewmodel_ink_material = _ink_material.duplicate() as ShaderMaterial
	_viewmodel_ink_material.set_shader_parameter(&"normal_threshold", 0.75)
	_viewmodel_ink_material.set_shader_parameter(&"depth_threshold", 0.15)
	_neon_material = _edge_material(Color(Tokens.NEON_EDGE, Tokens.NEON_EDGE_ALPHA),
		Tokens.NEON_EDGE_ENERGY, Tokens.NEON_EDGE_PX)
	# Solo siluetas, y solo del lado del objeto: es un filo, no un dibujo.
	_neon_material.set_shader_parameter(&"normal_threshold", 3.0)
	_neon_material.set_shader_parameter(&"near_side_only", true)
	_neon_material.set_shader_parameter(&"depth_threshold", 0.08)
	_build_broadcast_layer()
	get_tree().node_added.connect(_on_node_added)
	EventBus.settings_applied.connect(refresh)
	EventBus.player_hit.connect(_on_player_hit)
	refresh()


func _process(delta: float) -> void:
	if style != Style.NEON:
		return
	# Solo en partida: el menu y la tienda son pantallas, no la transmision.
	var player := Players.local() as CharacterBody3D
	_broadcast_layer.visible = player != null
	if player == null:
		return
	_hit_pulse = maxf(_hit_pulse - PULSE_DECAY * delta, 0.0)
	var speed: float = Vector3(player.velocity.x, player.velocity.y * 0.5, player.velocity.z).length()
	var speed_pulse: float = smoothstep(SPEED_PULSE_FROM, SPEED_PULSE_TO, speed) * SPEED_PULSE_MAX
	var pulse: float = maxf(_hit_pulse, speed_pulse)
	if bool(SettingsManager.get_value("accessibility/reduce_flashing")):
		pulse = 0.0
	_broadcast_material.set_shader_parameter(&"pulse", pulse)


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


func set_style(value: Style) -> void:
	if value == style:
		return
	_clear()
	style = value
	if _broadcast_layer != null:
		_broadcast_layer.visible = false
	if style != Style.STANDARD and is_inside_tree():
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


## Las lineas de una camara, o null si no tiene.
func get_edges(camera: Camera3D) -> MeshInstance3D:
	return camera.get_node_or_null(EDGE_NODE_NAME) as MeshInstance3D


func is_broadcast_visible() -> bool:
	return _broadcast_layer != null and _broadcast_layer.visible


# Private

func _edge_material(color: Color, energy: float, width: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = EDGE_SHADER
	material.set_shader_parameter(&"line_color", color)
	material.set_shader_parameter(&"line_energy", energy)
	material.set_shader_parameter(&"line_px", width)
	# Antes que cualquier otro transparente: un fogonazo o un numero de daño se
	# dibujan encima de la linea, no debajo.
	material.render_priority = Material.RENDER_PRIORITY_MIN
	return material


## Capa 1, como la HUD, pero hija de un autoload: los autoloads van antes que la
## escena en el arbol, y a igual capa dibuja primero el que va antes. Asi queda
## encima del mundo y del arma (capa 0) y debajo de la HUD.
func _build_broadcast_layer() -> void:
	_broadcast_layer = CanvasLayer.new()
	_broadcast_layer.name = "Broadcast"
	_broadcast_layer.layer = 1
	_broadcast_layer.visible = false
	add_child(_broadcast_layer)
	_broadcast_material = ShaderMaterial.new()
	_broadcast_material.shader = BROADCAST_SHADER
	_broadcast_material.set_shader_parameter(&"shadow_tint", Tokens.BROADCAST_SHADOW)
	var rect := ColorRect.new()
	rect.material = _broadcast_material
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_broadcast_layer.add_child(rect)


func _on_player_hit(amount: float, _cause: StringName) -> void:
	_hit_pulse = minf(_hit_pulse + amount / PULSE_FULL_DAMAGE, 1.0)


func _on_node_added(node: Node) -> void:
	if style == Style.STANDARD:
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
		if is_instance_valid(node) and style != Style.STANDARD:
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
	if style != Style.TOON:
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
## En neon el arma no lleva filo: solo el mundo.
func _add_edges(camera: Camera3D) -> void:
	if get_edges(camera) != null:
		return
	var in_subviewport: bool = camera.get_viewport() is SubViewport
	var material: ShaderMaterial = _neon_material
	if style == Style.TOON:
		material = _viewmodel_ink_material if in_subviewport else _ink_material
	elif in_subviewport:
		return
	var quad := MeshInstance3D.new()
	quad.name = EDGE_NODE_NAME
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	quad.mesh = mesh
	quad.material_override = material
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


## Deja todo como en el estandar: materiales, lineas y la pasada de transmision.
func _clear() -> void:
	for material: BaseMaterial3D in _converted:
		restore_material(material)
	_converted.clear()
	for quad: MeshInstance3D in _edges:
		if is_instance_valid(quad):
			# free() y no queue_free(): al cambiar de estilo la camara recibe su
			# quad nuevo en el mismo frame, y el viejo con el mismo nombre todavia
			# colgado haria que get_edges() crea que ya tiene.
			quad.get_parent().remove_child(quad)
			quad.free()
	_edges.clear()
	_pending.clear()
	_hit_pulse = 0.0
