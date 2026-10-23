class_name ViewInterpolator
extends Node
## La camara del jugador, dibujada entre dos ticks de fisica en vez de en el
## ultimo.
##
## El cuerpo se mueve a 60 Hz (`move_and_slide()` en `_physics_process`) y la
## pantalla puede ir a 144. Sin esto la camara salta al tick nuevo y se queda
## quieta hasta el siguiente: a 144 Hz son dos o tres frames iguales y uno que
## avanza, que es exactamente lo que se ve como tirones al correr.
##
## La interpolacion del motor (`physics/common/physics_interpolation`) no alcanza
## sola para la camara, por como esta armado el jugador:
##
##   Player      posicion: fisica       giro (yaw): _process, la mirada
##   HeadPivot   cabeceo: _process, la mirada; altura: tweens del slide y la muerte
##   ViewBob     paso, inclinacion, aterrizaje: _physics_process (CameraFeel)
##   CameraRig   patada del arma: _process (CameraRecoil)
##   Camera3D
##
## El motor interpola lo que cambia en ticks de fisica y atrasa hasta un tick lo
## que cambia en `_process`: la mirada llegaria tarde, que es peor que el tiron.
## Asi que la camara sale de la cadena (`top_level`, sin interpolacion del motor)
## y se arma aca cada frame con cada parte en su verdad: la posicion del cuerpo
## interpolada, el bob interpolado a mano, y la mirada y la patada tal cual estan.
##
## Solo dibujo: las balas salen de HeadPivot, que sigue siendo la verdad de fisica.

var body: Node3D
var head: Node3D
var view_node: Node3D
var rig: Node3D
var camera: Camera3D

## La camara respecto de CameraRig, como estaba autorada.
var _camera_local: Transform3D = Transform3D.IDENTITY
## ViewBob en los dos ultimos ticks, para interpolarlo a mano: cambia en fisica,
## pero su padre cambia en `_process` y el del motor lo atrasaria con el.
var _bob_previous: Transform3D = Transform3D.IDENTITY
var _bob_current: Transform3D = Transform3D.IDENTITY


## Devuelve false si falta alguna pieza; el jugador se queda con la camara de
## siempre.
func setup(player_body: Node3D, player_head: Node3D, bob_node: Node3D, recoil_rig: Node3D,
		player_camera: Camera3D) -> bool:
	body = player_body
	head = player_head
	view_node = bob_node
	rig = recoil_rig
	camera = player_camera
	if body == null or head == null or view_node == null or rig == null or camera == null:
		return false
	# Despues de todo lo que mueve la cadena: la mirada (Player), CameraFeel en
	# fisica y CameraRecoil en `_process`.
	process_priority = 100
	process_physics_priority = 100
	_camera_local = camera.transform
	camera.top_level = true
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	snap()
	return true


## Olvida el bob anterior. Despues de un teleport, o el primer frame dibujaria
## el bob de antes mezclado con el de ahora.
func snap() -> void:
	_bob_current = view_node.transform
	_bob_previous = _bob_current
	_sync(1.0)


func _physics_process(_delta: float) -> void:
	_bob_previous = _bob_current
	_bob_current = view_node.transform


func _process(_delta: float) -> void:
	_sync(Engine.get_physics_interpolation_fraction())


func _sync(fraction: float) -> void:
	var bob: Transform3D = _bob_previous.interpolate_with(_bob_current, fraction)
	# El giro del cuerpo tal cual (es la mirada) y su posicion interpolada.
	var base := Transform3D(body.global_basis, body.get_global_transform_interpolated().origin)
	camera.global_transform = base * head.transform * bob * rig.transform * _camera_local
