class_name ViewmodelGrappleLauncher
extends Node3D
## El lanzador del gancho en la muñeca izquierda, y el cable que sale de el.
##
## El gancho no tenia origen: el jugador apretaba el boton y salia volando hacia
## un ancla sin que nada en pantalla lo tirara. Esto lo pone en el unico lugar que
## se mira toda la run, el antebrazo que sostiene el arma, y le da un cable cian
## (lo suyo, ley de color) desde la boca hasta el ancla.
##
## Vive dentro del rig del viewmodel, que tiene su propio mundo, pero el cable va
## al ancla, que esta en el mundo del juego. Se dibuja alla, arrancando desde el
## punto del mundo que cae en pantalla exactamente donde se ve la boca del
## lanzador: las dos camaras tienen otro FOV, asi que no alcanza con copiar la
## posicion - hay que estirarla en X e Y por la relacion de las tangentes.

const LAUNCHER_MESH: Mesh = preload("res://assets/models/meshes/grapple_launcher.res")

## Donde sale el cable, en el espacio del lanzador (la boca, ver
## tools/build_gadget_meshes.gd).
const NOZZLE: Vector3 = Vector3(0.0, 0.03, -0.16)
## Lo que retrocede el lanzador al disparar, y cuanto tarda en volver.
const KICK_BACK: float = 0.025
const KICK_TIME: float = 0.18
## El cable sale, no aparece: llega al ancla en este tiempo.
const CABLE_TRAVEL_TIME: float = 0.08
const CABLE_THICKNESS: float = 0.018
## Brillo de los acentos en reposo y con el gancho enganchado.
const GLOW_IDLE: float = 1.2
const GLOW_ACTIVE: float = 4.0

var _mesh: MeshInstance3D
var _glow: StandardMaterial3D
var _cable: MeshInstance3D
var _anchor: Vector3 = Vector3.ZERO
var _grappling: bool = false
var _since_fired: float = 999.0


func _ready() -> void:
	# Despues de ViewInterpolator: el cable sale de donde la camara del juego se
	# dibuja este frame, y esa la arma el interpolador. Antes que el, el cable
	# salia de la camara del frame anterior y se despegaba del lanzador al correr.
	process_priority = ViewInterpolator.PROCESS_PRIORITY + 1
	_mesh = MeshInstance3D.new()
	_mesh.name = &"Launcher"
	_mesh.mesh = LAUNCHER_MESH
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	var body := StandardMaterial3D.new()
	body.albedo_color = Tokens.RAISED
	body.roughness = 0.6
	body.metallic = 0.4
	_glow = StandardMaterial3D.new()
	_glow.albedo_color = Tokens.PLAYER
	_glow.emission_enabled = true
	_glow.emission = Tokens.PLAYER
	_glow.emission_energy_multiplier = GLOW_IDLE
	_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Copia propia con sus materiales, y no overrides por superficie: el brillo
	# sube y baja por instancia, y hay un lanzador por juego de brazos.
	var own := LAUNCHER_MESH.duplicate() as ArrayMesh
	if own != null:
		for surface: int in own.get_surface_count():
			var is_accent: bool = own.surface_get_name(surface) == "accent"
			own.surface_set_material(surface, _glow if is_accent else body)
		_mesh.mesh = own

	EventBus.grapple_started.connect(_on_grapple_started)
	EventBus.grapple_ended.connect(_on_grapple_ended)


func _exit_tree() -> void:
	if _cable != null and is_instance_valid(_cable):
		_cable.queue_free()
	_cable = null


func is_grappling() -> bool:
	return _grappling


func _process(delta: float) -> void:
	_since_fired += delta
	var kick: float = 0.0
	if _since_fired < KICK_TIME:
		var t: float = _since_fired / KICK_TIME
		kick = KICK_BACK * (1.0 - t) * (1.0 - t)
	_mesh.position = Vector3(0.0, 0.0, kick)
	var glow_target: float = GLOW_ACTIVE if _grappling else GLOW_IDLE
	_glow.emission_energy_multiplier = lerpf(_glow.emission_energy_multiplier, glow_target,
		clampf(delta * 12.0, 0.0, 1.0))
	_update_cable()


# Private

## Solo el brazo que se ve dispara: hay un juego de brazos por arma, y los de las
## armas guardadas tambien escuchan el EventBus.
func _on_grapple_started(anchor: Vector3) -> void:
	if not is_visible_in_tree():
		return
	_anchor = anchor
	_grappling = true
	_since_fired = 0.0


func _on_grapple_ended() -> void:
	_grappling = false
	if _cable != null and is_instance_valid(_cable):
		_cable.visible = false


func _update_cable() -> void:
	if not _grappling or not is_visible_in_tree():
		if _cable != null and is_instance_valid(_cable):
			_cable.visible = false
		return
	var world_camera: Camera3D = _world_camera()
	var view_camera: Camera3D = get_viewport().get_camera_3d()
	if world_camera == null or view_camera == null or world_camera == view_camera:
		return
	var start: Vector3 = _nozzle_in_world(world_camera, view_camera)
	var travel: float = clampf(_since_fired / CABLE_TRAVEL_TIME, 0.0, 1.0)
	var end: Vector3 = start.lerp(_anchor, travel)
	var length: float = start.distance_to(end)
	if length < 0.01:
		return
	var cable: MeshInstance3D = _ensure_cable(world_camera)
	cable.visible = true
	var direction: Vector3 = (end - start) / length
	var aim := Basis.looking_at(direction,
		Vector3.UP if absf(direction.y) < 0.99 else Vector3.FORWARD)
	# Estirado sobre su propio Z (scaled_local): `scaled()` escala en ejes globales
	# y torcia el cable hacia cualquier lado.
	cable.global_transform = Transform3D(aim.scaled_local(Vector3(1.0, 1.0, length)),
		start.lerp(end, 0.5))


## El punto del mundo del juego que la camara del juego ve donde la camara del
## viewmodel ve la boca del lanzador.
func _nozzle_in_world(world_camera: Camera3D, view_camera: Camera3D) -> Vector3:
	var local: Vector3 = view_camera.global_transform.affine_inverse() \
		* (_mesh.global_transform * NOZZLE)
	var stretch: float = tan(deg_to_rad(world_camera.fov) * 0.5) \
		/ tan(deg_to_rad(view_camera.fov) * 0.5)
	return world_camera.global_transform * Vector3(local.x * stretch, local.y * stretch, local.z)


## La camara del juego, no la de este SubViewport: la de la ventana.
func _world_camera() -> Camera3D:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_camera_3d()


func _ensure_cable(world_camera: Camera3D) -> MeshInstance3D:
	if _cable != null and is_instance_valid(_cable):
		return _cable
	var box := BoxMesh.new()
	box.size = Vector3(CABLE_THICKNESS, CABLE_THICKNESS, 1.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Tokens.PLAYER
	material.emission_enabled = true
	material.emission = Tokens.PLAYER
	material.emission_energy_multiplier = 2.5
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material = material
	_cable = MeshInstance3D.new()
	_cable.name = &"GrappleCable"
	_cable.mesh = box
	_cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cable.top_level = true
	# Colgado de la camara del juego para vivir en su mundo; top_level para que
	# no herede su transform, el cable se ubica en coordenadas globales.
	world_camera.add_child(_cable)
	return _cable
