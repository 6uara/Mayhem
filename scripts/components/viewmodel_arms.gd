class_name ViewmodelArms
extends Node3D
## Los brazos que sostienen el arma del viewmodel: el rig de fp_arms.glb, con IK.
##
## Reemplaza a los cilindros placeholder. Lo que se conserva de ellos es el
## contrato con `WeaponComponent`: los brazos no se cuelgan del pivot del arma sino
## al lado, y les copia la posicion y el kick pero no el giro de recarga. La
## recarga es una vuelta entera del arma; unos brazos atornillados a ella girarian
## por toda la pantalla. Mientras el arma gira, las manos la sueltan y la esperan.
##
## Las manos se ubican midiendo la malla del arma, igual que la boca del cañon en
## `WeaponComponent._align_muzzle_to_barrel()`: la derecha en la empuñadura, la
## izquierda bajo el guardamanos. Un arma nueva queda agarrada sin tocar nada. El
## codo lo pone `ViewmodelArmIK`; los dedos, los clips del glb.
##
## Lo que se anima por estado y no por clip - igual que el giro de recarga - es a
## donde va cada mano: el clip de recarga se recorre por el progreso de la
## recarga, no por reloj, asi que una recarga mas rapida por mejora sigue cuadrando
## y una cortada vuelve al agarre sin estado que limpiar.

const ARMS_SCENE: PackedScene = preload("res://assets/models/Arms/fp_arms.glb")
const IK_SCRIPT := preload("res://scripts/components/viewmodel_arm_ik.gd")
const LAUNCHER_SCRIPT := preload("res://scripts/components/viewmodel_grapple_launcher.gd")

## El lanzador del gancho, sobre el dorso del antebrazo izquierdo: que fraccion
## del antebrazo hacia la muñeca, y cuanto sobresale de la manga (en metros del
## rig sin escalar).
const LAUNCHER_ALONG: float = 0.7
const LAUNCHER_LIFT: float = 0.04
## Pegado al ojo como esta el antebrazo izquierdo, a tamaño real tapaba medio
## guardamanos.
const LAUNCHER_SCALE: float = 0.8

## Entre los dos hombros, en el espacio de la camara del viewmodel. Atras y abajo
## del ojo: el brazo entra en cuadro desde el borde, y lo que se ve es antebrazo y
## mano. Mas adelante, el codo se pliega hasta salir por arriba del arma.
const SHOULDER_CENTRE: Vector3 = Vector3(0.03, -0.3, -0.19)
## El rig mide como una persona, y el rifle pide estirar la izquierda hasta el
## guardamanos a casi 60 cm del ojo. Un poco mas largo que real llega sin trabarse
## recto, que es lo que se nota.
const ARM_SCALE: float = 0.75
## Hacia donde salen los codos, desde cada hombro: abajo y hacia afuera.
const RIGHT_POLE: Vector3 = Vector3(0.45, -0.6, 0.1)
const LEFT_POLE: Vector3 = Vector3(-0.5, -0.55, 0.0)
## Un arma mas corta que esto se sostiene con las dos manos juntas (pistola).
const TWO_HAND_REACH: float = 0.32

## Orientacion de cada mano en el agarre, en el espacio de la camara: hacia donde
## van los nudillos y hacia donde mira la palma. La derecha envuelve la empuñadura
## con la palma hacia el centro del arma; la izquierda la sostiene desde abajo.
const RIGHT_FORWARD: Vector3 = Vector3(-0.1, 0.25, -1.0)
const RIGHT_PALM: Vector3 = Vector3(-1.0, 0.0, -0.1)
const LEFT_FORWARD: Vector3 = Vector3(0.65, 0.2, -0.75)
const LEFT_PALM: Vector3 = Vector3(0.25, 1.0, 0.15)
## De la muñeca al centro de la palma, en metros del rig sin escalar: el punto de
## agarre es donde va la palma, y el IK mueve la muñeca.
const PALM_REACH: float = 0.09
const PALM_DEPTH: float = 0.035

## Sacar el arma: las manos suben desde abajo hasta el agarre.
const EQUIP_TIME: float = 0.32
const EQUIP_DROP: Vector3 = Vector3(0.0, -0.32, 0.12)
## Recarga: la derecha se abre y baja un poco; la izquierda baja a buscar el
## cargador fuera de cuadro y vuelve por abajo del arma.
const RELOAD_RIGHT_DROP: Vector3 = Vector3(0.03, -0.06, 0.06)
const RELOAD_BELT: Vector3 = Vector3(-0.12, -0.38, 0.2)
const RELOAD_MAGWELL: Vector3 = Vector3(0.0, -0.09, 0.02)
## Al tirar el gancho la izquierda suelta el arma y se adelanta, con el dorso
## arriba: el lanzador va en el dorso del antebrazo, y con la pistola (las dos
## manos juntas, el antebrazo fuera de cuadro) es la unica forma de que se vea
## salir el cable. En el espacio de la camara.
const GRAPPLE_HAND: Vector3 = Vector3(-0.07, -0.12, -0.52)
## La mano se dobla hacia abajo: con la muñeca recta los dedos tapaban la boca
## del lanzador y el cable parecia salir de la mano.
const GRAPPLE_FORWARD: Vector3 = Vector3(0.2, -0.45, -1.0)
const GRAPPLE_PALM: Vector3 = Vector3(0.4, -1.0, 0.0)
## Lo que tarda la mano en ir y en volver.
const GRAPPLE_RAISE_TIME: float = 0.12

const CLIP_IDLE: StringName = &"grip_idle"
const CLIP_FIRE: StringName = &"fire"
const CLIP_RELOAD: StringName = &"reload"
const CLIP_EQUIP: StringName = &"equip"

var _rig: Node3D
var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _ik: IK_SCRIPT
var _grip: Vector3 = Vector3.ZERO
var _support: Vector3 = Vector3.ZERO
var _shoulder_centre: Vector3 = Vector3.ZERO
var _reload_progress: float = 0.0
var _equip_left: float = 0.0
var _launcher: Node3D
## 0 con la mano en el arma, 1 con el brazo adelante tirando el gancho.
var _grapple_blend: float = 0.0


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)


## Arma los dos brazos para un arma cuya malla ocupa `weapon_bounds`, medida en
## el espacio de este nodo. `pivot_offset` es donde queda este nodo respecto de
## la camara, para poder poner los hombros en el espacio de la camara.
func build(weapon_bounds: AABB, pivot_offset: Vector3) -> void:
	for child: Node in get_children():
		child.queue_free()
	_rig = null
	_skeleton = null
	_player = null
	_ik = null
	if weapon_bounds.size == Vector3.ZERO:
		return

	_grip = grip_point(weapon_bounds)
	_support = support_point(weapon_bounds)
	_shoulder_centre = SHOULDER_CENTRE - pivot_offset

	_rig = ARMS_SCENE.instantiate() as Node3D
	_rig.name = &"Rig"
	add_child(_rig)
	_skeleton = _find(_rig, "Skeleton3D") as Skeleton3D
	_player = _find(_rig, "AnimationPlayer") as AnimationPlayer
	for mesh: Node in _rig.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _skeleton == null:
		push_warning("ViewmodelArms: fp_arms.glb has no Skeleton3D")
		return
	_place_rig()

	_ik = IK_SCRIPT.new()
	_ik.name = &"ArmIK"
	_ik.space = self
	_skeleton.add_child(_ik)
	_ik.bind_arm(_ik.right, _skeleton, "R", true)
	_ik.bind_arm(_ik.left, _skeleton, "L", false)
	_mount_grapple_launcher()

	if _player != null and _player.has_animation(CLIP_IDLE):
		_player.get_animation(CLIP_IDLE).loop_mode = Animation.LOOP_LINEAR
		_player.play(CLIP_IDLE)
	_equip_left = EQUIP_TIME
	_update_targets()


## Lo llama WeaponComponent en cada disparo: el indice aprieta el gatillo.
func play_fire() -> void:
	if _player == null or _reload_progress > 0.0 or not _player.has_animation(CLIP_FIRE):
		return
	_player.play(CLIP_FIRE)
	_player.seek(0.0, true)
	_player.queue(CLIP_IDLE)


## 0 sin recargar, 1 al terminar. Ver `WeaponComponent.get_reload_progress()`.
func set_reload_progress(progress: float) -> void:
	var was_reloading: bool = _reload_progress > 0.0
	_reload_progress = clampf(progress, 0.0, 1.0)
	if was_reloading and _reload_progress <= 0.0 and _player != null:
		_player.play(CLIP_IDLE, 0.1)


## La empuñadura: tercio de atras, parte baja. Adelante es -Z.
static func grip_point(bounds: AABB) -> Vector3:
	var centre: Vector3 = bounds.get_center()
	return Vector3(centre.x,
		bounds.position.y + bounds.size.y * 0.25,
		bounds.end.z - bounds.size.z * 0.3)


## El guardamanos, o la otra mano pegada a la primera si el arma es corta.
##
## A media altura de la caja y no abajo: la caja del rifle incluye el cargador,
## que cuelga muy por debajo del guardamanos, y una palma puesta al 30% del alto
## sostenia el aire bajo el caño.
static func support_point(bounds: AABB) -> Vector3:
	var grip: Vector3 = grip_point(bounds)
	if bounds.size.z < TWO_HAND_REACH:
		return grip + Vector3(-0.035, -0.035, -0.01)
	var centre: Vector3 = bounds.get_center()
	return Vector3(centre.x,
		bounds.position.y + bounds.size.y * 0.55,
		bounds.position.z + bounds.size.z * 0.3)


## Donde tiene que estar cada muñeca ahora mismo, en el espacio de este nodo.
## Publico para los tests: es lo unico de los brazos que se puede medir sin ver.
func get_wrist_targets() -> Array[Vector3]:
	if _ik == null:
		return []
	return [_ik.right.wrist, _ik.left.wrist]


func _process(delta: float) -> void:
	if _ik == null:
		return
	_equip_left = maxf(_equip_left - delta, 0.0)
	var grappling: bool = _launcher != null and bool(_launcher.call(&"is_grappling"))
	_grapple_blend = move_toward(_grapple_blend, 1.0 if grappling else 0.0,
		delta / GRAPPLE_RAISE_TIME)
	_update_targets()
	_update_clip()


# Private

## Gira el rig para que mire a -Z (llega mirando a +Z, como sale de Blender) y lo
## mueve para que el punto medio entre los hombros caiga en `_shoulder_centre`.
func _place_rig() -> void:
	var orient := Basis(Vector3.UP, PI).scaled(Vector3.ONE * ARM_SCALE)
	var to_rig: Transform3D = _relative_transform(_rig, _skeleton)
	var left_shoulder: Vector3 = to_rig * _bone_rest_origin("upper_arm.L")
	var right_shoulder: Vector3 = to_rig * _bone_rest_origin("upper_arm.R")
	var centre: Vector3 = (left_shoulder + right_shoulder) * 0.5
	_rig.transform = Transform3D(orient, _shoulder_centre - orient * centre)


## Cuelga el lanzador del antebrazo izquierdo, apuntando a la mano. Se ubica en la
## pose de reposo (brazos en T, palmas abajo: el dorso mira a +Y) y despues el
## BoneAttachment3D lo lleva con el hueso, IK incluida.
func _mount_grapple_launcher() -> void:
	var forearm: int = _skeleton.find_bone("forearm.L")
	var hand: int = _skeleton.find_bone("hand.L")
	if forearm < 0 or hand < 0:
		return
	var forearm_rest: Transform3D = _skeleton.get_bone_global_rest(forearm)
	var wrist: Vector3 = _skeleton.get_bone_global_rest(hand).origin
	var along: Vector3 = (wrist - forearm_rest.origin).normalized()
	var at: Vector3 = forearm_rest.origin.lerp(wrist, LAUNCHER_ALONG) \
		+ Vector3.UP * LAUNCHER_LIFT
	var mount := Transform3D(Basis.looking_at(along, Vector3.UP).scaled(
		Vector3.ONE * LAUNCHER_SCALE), at)

	var attachment := BoneAttachment3D.new()
	attachment.name = &"LauncherMount"
	_skeleton.add_child(attachment)
	attachment.bone_name = "forearm.L"
	var launcher: Node3D = LAUNCHER_SCRIPT.new()
	launcher.name = &"GrappleLauncher"
	launcher.transform = forearm_rest.affine_inverse() * mount
	attachment.add_child(launcher)
	_launcher = launcher


func _bone_rest_origin(bone_name: String) -> Vector3:
	var bone: int = _skeleton.find_bone(bone_name)
	if bone < 0:
		return Vector3.ZERO
	return _skeleton.get_bone_global_rest(bone).origin


func _update_targets() -> void:
	var equip: float = 1.0 - smoothstep(0.0, 1.0, 1.0 - _equip_left / EQUIP_TIME)
	var drop: Vector3 = EQUIP_DROP * equip
	var p: float = _reload_progress

	var right_palm: Vector3 = _grip + RELOAD_RIGHT_DROP * sin(PI * p) + drop
	var left_palm: Vector3 = _reload_left_hand(p) + drop
	_aim_hand(_ik.right, right_palm, RIGHT_FORWARD, RIGHT_PALM)
	var raise: float = smoothstep(0.0, 1.0, _grapple_blend)
	# De la camara a este nodo: lo mismo que se le resto a los hombros.
	var grapple_palm: Vector3 = GRAPPLE_HAND + (_shoulder_centre - SHOULDER_CENTRE)
	_aim_hand(_ik.left, left_palm.lerp(grapple_palm, raise),
		LEFT_FORWARD.lerp(GRAPPLE_FORWARD, raise), LEFT_PALM.lerp(GRAPPLE_PALM, raise))

	var half_width: float = absf(_shoulder_from_rig("upper_arm.R").x
		- _shoulder_from_rig("upper_arm.L").x) * 0.5
	_ik.right.pole = _shoulder_centre + Vector3(half_width, 0.0, 0.0) + RIGHT_POLE
	_ik.left.pole = _shoulder_centre - Vector3(half_width, 0.0, 0.0) + LEFT_POLE


## La mano izquierda durante la recarga: suelta, baja al cinturon, vuelve con el
## cargador por abajo del arma, lo mete y regresa al guardamanos. Cada tramo con
## smoothstep para que no arranque ni frene de golpe.
func _reload_left_hand(p: float) -> Vector3:
	if p <= 0.0:
		return _support
	var belt: Vector3 = _grip + RELOAD_BELT
	var magwell: Vector3 = _grip.lerp(_support, 0.4) + RELOAD_MAGWELL
	var seated: Vector3 = _grip.lerp(_support, 0.4) + Vector3(0.0, -0.04, 0.0)
	var keys: Array[Vector3] = [_support, _support, belt, belt, magwell, seated, _support, _support]
	var times: Array[float] = [0.0, 0.1, 0.32, 0.42, 0.62, 0.72, 0.9, 1.0]
	for i: int in range(1, times.size()):
		if p <= times[i]:
			var t: float = smoothstep(times[i - 1], times[i], p)
			return keys[i - 1].lerp(keys[i], t)
	return _support


## Pone la muñeca de modo que la palma caiga en `palm_point`, con la mano
## orientada como piden `forward` y `palm`.
func _aim_hand(arm: IK_SCRIPT.Arm, palm_point: Vector3, forward: Vector3,
		palm: Vector3) -> void:
	var f: Vector3 = forward.normalized()
	var n: Vector3 = (palm - f * palm.dot(f)).normalized()
	arm.forward = f
	arm.palm = n
	arm.wrist = palm_point - (f * PALM_REACH + n * PALM_DEPTH) * ARM_SCALE


func _shoulder_from_rig(bone_name: String) -> Vector3:
	if _rig == null:
		return Vector3.ZERO
	return _rig.transform * (_relative_transform(_rig, _skeleton)
		* _bone_rest_origin(bone_name))


## El clip de dedos que toca: recarga y equipar se recorren por progreso, el
## resto corre solo (reposo en loop, disparo encima).
func _update_clip() -> void:
	if _player == null:
		return
	if _reload_progress > 0.0 and _player.has_animation(CLIP_RELOAD):
		_seek(CLIP_RELOAD, _reload_progress)
	elif _equip_left > 0.0 and _player.has_animation(CLIP_EQUIP):
		_seek(CLIP_EQUIP, 1.0 - _equip_left / EQUIP_TIME)
	elif not _player.is_playing() or _player.current_animation == CLIP_EQUIP \
			or _player.current_animation == CLIP_RELOAD:
		_player.play(CLIP_IDLE, 0.1)


func _seek(clip: StringName, progress: float) -> void:
	if _player.assigned_animation != clip:
		_player.play(clip)
	_player.pause()
	_player.seek(_player.get_animation(clip).length * progress, true)


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_equip_left = EQUIP_TIME


func _find(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child: Node in node.get_children():
		var found: Node = _find(child, type_name)
		if found != null:
			return found
	return null


func _relative_transform(root: Node3D, target: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var node: Node3D = target
	while node != null and node != root:
		result = node.transform * result
		node = node.get_parent() as Node3D
	return result
