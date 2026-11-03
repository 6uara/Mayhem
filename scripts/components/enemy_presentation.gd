class_name EnemyPresentation
extends RefCounted
## Como se ve un enemigo: el modelo del arquetipo (o la capsula grey-box), el
## destello de golpe y de preparacion, el contorno en el color del arquetipo, el
## halo y el haz del Healer, y el anillo de la Cacería.
##
## Salio de `enemy.gd` (2026-11-03), que pasaba las 2700 lineas: la
## presentacion era el bloque mas grande que no tocaba ni la IA ni la fisica, y
## se editaba por motivos distintos (un modelo nuevo, un shader) que el resto.
## `Enemy` sigue decidiendo **cuando** brilla (golpe, telegrafo, cura, espoleta);
## esto decide **como**.
##
## RefCounted y no Node: no tiene ciclo propio, todo lo que cuelga en el arbol
## (el modelo, la animacion, el anillo) cuelga del enemigo. Pooleado con el: un
## cuerpo que vuelve del pool conserva su modelo si el arquetipo no cambio.

const MODEL_MOTION_SCRIPT := preload("res://scripts/components/enemy_model_motion.gd")
const OUTLINE_SHADER: Shader = preload("res://assets/shaders/enemy_outline.gdshader")

var enemy: Enemy

## The rigged model currently attached, and the scene it came from. Kept between
## spawns: the enemy is pooled, and re-instantiating a model every time one left
## the pool would pay exactly the cost the pool exists to avoid. Only a change of
## archetype rebuilds it.
var model: Node3D
var model_source: PackedScene
## Every MeshInstance3D inside the model, and the one material laid over all of
## them to light the whole bot up at once.
var model_meshes: Array[MeshInstance3D] = []
var glow_material: StandardMaterial3D
## El contorno del modelo en el color del arquetipo (assets/shaders/
## enemy_outline.gdshader). Uno por enemigo: el destello va encadenado a el
## (`next_pass`) y se prende y apaga por enemigo.
var outline_material: ShaderMaterial
## Flota, oscila, se inclina: la animacion procedural del modelo, cuando el
## arquetipo pide alguna o el modelo trae clips. Ver EnemyModelMotion.
var motion: MODEL_MOTION_SCRIPT
## Caja de las mallas del modelo en su propio espacio, sin su transform. La mide
## `_apply_model()` una vez por modelo y la usa `model_fit_height`.
var model_bounds: AABB = AABB()
## El material de la capsula grey-box, cuando no hay modelo.
var material: StandardMaterial3D
## Si el overlay del destello esta puesto en el modelo. Ver `_set_overlay()`.
var _overlay_on: bool = false
## El anillo de recompensa sobre la cabeza de un marcado. Se crea la primera vez
## que este cuerpo sale marcado y despues solo se prende y apaga.
var _mark_ring: MeshInstance3D


func _init(owner_enemy: Enemy) -> void:
	enemy = owner_enemy


## Modelo, capsula y materiales para el arquetipo de `enemy.data`. Lo llama
## `Enemy.setup()` cada vez que el cuerpo sale del pool.
func apply() -> void:
	var data: EnemyData = enemy.data
	_apply_model()
	var mesh_instance: MeshInstance3D = enemy.mesh_instance
	if mesh_instance == null:
		return
	# The primitive is the fallback silhouette. With a model attached it is still
	# here - the archetype may be swapped for one without a model on the next
	# trip out of the pool - it is simply not drawn.
	mesh_instance.visible = model == null
	if data.mesh != null:
		mesh_instance.mesh = data.mesh
	mesh_instance.scale = Vector3.ONE * data.body_scale
	# Centrada sobre la capsula, igual que _resize_capsule hace con las formas.
	#
	# Estaba fija en 0.9 desde la escena, que es la mitad de la capsula de 1.8 con
	# la que se autoro - o sea, correcta para un arquetipo de 1.8m de alto y para
	# ninguno de los que hay. Las mallas ya vienen con el pivote en su propio
	# centro (es lo que garantiza tools/bake_enemy_meshes.gd), asi que la mitad de
	# la altura es donde va. Los arquetipos con model_scene no lo notan: ahi esta
	# primitiva no se dibuja.
	mesh_instance.position.y = data.collision_height * 0.5
	if material == null:
		material = StandardMaterial3D.new()
		mesh_instance.material_override = material
	material.albedo_color = data.body_color
	material.emission_enabled = true
	material.emission = enemy.flash_color
	material.emission_energy_multiplier = 0.0


## One knob for "this enemy is lit up", whichever way it is being drawn: the
## emission on a capsule, the overlay on a model. Hit flashes and attack
## wind-ups both go through here, so neither has to know which it is looking at.
## `tint` existe para la curacion: es el mismo canal de destello, en verde. El
## color se pasa por llamada en vez de guardarse porque el estado de "de que
## color esta prendido" ya lo lleva el timer de destello del enemigo, y dos
## estados para una cosa es como quedan enemigos verdes para siempre.
func set_glow(amount: float, tint: Color) -> void:
	# Ceiling of 1.2 rather than 1.0: the hit flash deliberately overshoots the
	# brightest wind-up, and 1.2 * 2.5 is the 3.0 the capsule flash has always
	# used. The overlay cannot go past opaque, so it clamps a step earlier.
	var level: float = clampf(amount, 0.0, 1.2)
	if glow_material != null:
		glow_material.albedo_color = Color(tint, minf(level, 1.0) * 0.8)
		_set_overlay(level > 0.0)
	if material != null:
		material.emission = tint
		material.emission_energy_multiplier = level * 2.5


func glow_level() -> float:
	if glow_material != null:
		return glow_material.albedo_color.a
	return material.emission_energy_multiplier if material != null else 0.0


## El color del contorno ahora mismo: el del arquetipo, o el del gadget que lo
## esta afectando (EnemyStatusMarks).
func set_outline_color(colour: Color) -> void:
	if outline_material != null:
		outline_material.set_shader_parameter(&"outline_color", colour)


## The halo and the tether are what make the Healer readable; every other
## archetype turns them off.
func apply_silhouette_markers() -> void:
	var data: EnemyData = enemy.data
	var halo: MeshInstance3D = enemy.halo
	if halo != null:
		# Si el modelo trae su halo, el generado se apaga: dos anillos encimados no
		# se leen como uno. Sin modelo (grey-box) vuelve a ser el generado.
		var model_draws_halo: bool = data.model_has_halo and data.model_scene != null
		halo.visible = data.has_halo and not model_draws_halo
		if halo.visible:
			halo.position.y = data.halo_height
			halo.scale = Vector3.ONE * data.halo_radius
			tint(halo, data.body_color)
	if enemy.healer_tether != null:
		# Arranca desde la cabeza y no desde el centro del cuerpo: el haz que sale
		# del pecho queda tapado por el propio Healer cuando esta de frente.
		enemy.healer_tether.configure(data.has_tether, data.head_offset * 0.9)


## La marca de la Cacería: un anillo ambar sobre la cabeza. Ambar y circulo
## porque es la ley de color de REWARD ("esto paga"), no la del enemigo: lo que
## cambia de un marcado no es cuanto peligro tiene sino cuanto vale.
func set_marked(marked: bool) -> void:
	if not marked:
		if _mark_ring != null:
			_mark_ring.visible = false
		return
	if _mark_ring == null:
		_mark_ring = MeshInstance3D.new()
		_mark_ring.name = "MarkRing"
		var ring := TorusMesh.new()
		ring.inner_radius = 0.42
		ring.outer_radius = 0.55
		_mark_ring.mesh = ring
		_mark_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tint(_mark_ring, Tokens.REWARD)
		enemy.add_child(_mark_ring)
	_mark_ring.position.y = float(Tokens.ENEMY_HEIGHT.get(String(enemy.data.id), 2.0)) + 0.6
	_mark_ring.visible = true


static func tint(mesh: MeshInstance3D, colour: Color) -> void:
	var tinted := StandardMaterial3D.new()
	tinted.albedo_color = colour
	tinted.emission_enabled = true
	tinted.emission = colour
	tinted.emission_energy_multiplier = 1.4
	tinted.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = tinted


# Private

## Attaches the archetype's model, or takes down the one from the archetype this
## pooled body used to be.
func _apply_model() -> void:
	var data: EnemyData = enemy.data
	if data.model_scene == model_source:
		_place_model()
		return
	if model != null:
		model.queue_free()
	model = null
	model_meshes.clear()
	_overlay_on = false
	model_source = data.model_scene
	model_bounds = AABB()
	if model_source == null:
		# Sin modelo no hay nada que animar, y el componente quedaria
		# apuntando al que se acaba de liberar.
		_attach_motion()
		return
	model = model_source.instantiate() as Node3D
	if model == null:
		push_error("Enemy: %s model_scene is not a Node3D" % data.id)
		return
	enemy.add_child(model)
	# EnemyModelMotion lo anima en `_process`. Interpolado por el motor llegaria un
	# tick tarde; apagado sigue igual al cuerpo, que si se interpola.
	model.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_prune_authoring_nodes(model)
	_collect_model_meshes(model)
	model_bounds = _measure_model(model)
	_place_model()
	_attach_motion()


## Throws away what the modelling program packed alongside the model.
##
## A .fbx exported straight out of Blender keeps that file's camera and lights.
## Instanced once per enemy that is a light per enemy, and a Camera3D that makes
## itself current takes over the screen - the horde would be filming itself.
## Stripped here rather than in the import settings so it holds for any model
## anyone drops in later, whatever state its export was in.
func _prune_authoring_nodes(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Camera3D or child is Light3D:
			child.queue_free()
			continue
		_prune_authoring_nodes(child)


## Anima el modelo si el arquetipo lo pide o el modelo trae clips. Si no hay nada
## que hacer, el nodo no se queda: el pool corre muchos de estos a la vez.
func _attach_motion() -> void:
	if motion != null:
		motion.queue_free()
		motion = null
	if model == null:
		return
	var created := MODEL_MOTION_SCRIPT.new()
	enemy.add_child(created)
	if created.setup(model, enemy):
		motion = created
		return
	created.queue_free()


func _place_model() -> void:
	if model == null:
		return
	var data: EnemyData = enemy.data
	# El cabeceo va primero, en el espacio del modelo, y el yaw despues.
	var orient: Basis = Basis(Vector3.UP, deg_to_rad(data.model_yaw_degrees)) \
		* Basis(Vector3.RIGHT, deg_to_rad(data.model_pitch_degrees))
	var scale_factor: float = data.model_scale
	var fit_offset := Vector3.ZERO
	# Ajuste por altura: escala a `model_fit_height`, apoya la base en el piso y
	# centra la malla sobre el cuerpo. Se mide la caja ya orientada: medida antes,
	# un modelo acostado tomaba su espesor por altura y salia gigante.
	if data.model_fit_height > 0.0 and model_bounds.size.y > 0.0001:
		var oriented: AABB = Transform3D(orient, Vector3.ZERO) * model_bounds
		scale_factor = data.model_fit_height / oriented.size.y
		var centre: Vector3 = oriented.get_center()
		fit_offset = Vector3(-centre.x, -oriented.position.y, -centre.z) * scale_factor
	model.transform = Transform3D(orient.scaled(Vector3.ONE * scale_factor),
		data.model_offset + fit_offset)
	if motion != null:
		motion.capture_rest()


## La caja de todas las mallas del modelo, en el espacio del modelo sin su propio
## transform. Mismo recorrido que `WeaponComponent._model_bounds()`.
func _measure_model(root: Node3D) -> AABB:
	var out := AABB()
	var found: bool = false
	for mesh_node: MeshInstance3D in model_meshes:
		if mesh_node.mesh == null:
			continue
		var relative := Transform3D.IDENTITY
		var node: Node3D = mesh_node
		while node != null and node != root:
			relative = node.transform * relative
			node = node.get_parent() as Node3D
		var local: AABB = relative * mesh_node.mesh.get_aabb()
		out = local if not found else out.merge(local)
		found = true
	return out if found else AABB()


## An imported model brings its own materials, so the hit flash cannot be an
## albedo swap the way it is on a grey-box capsule. It is laid over the top
## instead: one unshaded material on every part, transparent until something
## lights it up.
##
## Puesto solo mientras brilla (`_set_overlay()`), encadenado detras del contorno.
## Un overlay transparente en cero igual se dibuja: cada parte de cada modelo
## pasaba dos veces por frame, la segunda en el pase transparente, para no
## pintar nada.
func _collect_model_meshes(node: Node) -> void:
	var mesh_node := node as MeshInstance3D
	if mesh_node != null:
		if glow_material == null:
			glow_material = StandardMaterial3D.new()
			glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glow_material.albedo_color = Color(enemy.flash_color, 0.0)
		mesh_node.material_overlay = _outline()
		model_meshes.append(mesh_node)
		_cap_emission(mesh_node)
	for child: Node in node.get_children():
		_collect_model_meshes(child)


## Baja la emision del modelo a `data.model_emission_max`. Toca el material
## importado, que comparten todas las instancias del modelo: el tope es el mismo
## para todas y aplicarlo dos veces no cambia nada.
func _cap_emission(mesh_node: MeshInstance3D) -> void:
	var data: EnemyData = enemy.data
	if data.model_emission_max <= 0.0 or mesh_node.mesh == null:
		return
	for surface: int in mesh_node.mesh.get_surface_count():
		var imported := mesh_node.get_active_material(surface) as BaseMaterial3D
		if imported != null and imported.emission_enabled:
			imported.emission_energy_multiplier = minf(
				imported.emission_energy_multiplier, data.model_emission_max)


func _set_overlay(on: bool) -> void:
	if on == _overlay_on:
		return
	_overlay_on = on
	# El contorno queda siempre puesto como overlay; el destello va encadenado
	# detras, asi que prenderlo no saca el borde y apagarlo no cuesta un pase.
	if outline_material != null:
		outline_material.next_pass = glow_material if on else null
		return
	for mesh_node: MeshInstance3D in model_meshes:
		if is_instance_valid(mesh_node):
			mesh_node.material_overlay = glow_material if on else null


## Los enemigos oscuros (el perro, el Ranger, el hechicero) desaparecian contra
## el piso oscuro de la arena. El borde los recorta en el color que ya los
## identifica en la capsula, el halo y el visor, sin tocar su textura.
func _outline() -> ShaderMaterial:
	if outline_material == null:
		outline_material = ShaderMaterial.new()
		outline_material.shader = OUTLINE_SHADER
		outline_material.set_shader_parameter(&"energy", Tokens.ENEMY_OUTLINE_ENERGY)
	outline_material.set_shader_parameter(&"outline_color", enemy.data.body_color)
	return outline_material
