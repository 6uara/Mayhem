extends GutTest
## La camara del jugador con la interpolacion de fisica prendida: se dibuja entre
## ticks, pero la mirada no llega tarde y las balas no se enteran.

var _player: Player
var _camera: Camera3D
var _rig: Node3D


func before_each() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	add_child_autofree(floor_body)
	_player = add_child_autofree(load("res://scenes/player/player.tscn").instantiate())
	_player.global_position = Vector3(0, 0.1, 0)
	_camera = _player.camera
	_rig = _camera.get_parent() as Node3D
	await wait_physics_frames(6)


func test_the_project_draws_between_physics_ticks() -> void:
	assert_true(ProjectSettings.get_setting("physics/common/physics_interpolation"),
		"sin esto, a 144 Hz el cuerpo avanza en saltos de 60")
	assert_true(get_tree().physics_interpolation)


func test_the_camera_is_driven_by_the_interpolator() -> void:
	assert_not_null(_player.view_interpolator, "el jugador arma su camara interpolada")
	assert_true(_camera.top_level, "la camara sale de la cadena")
	assert_eq(_camera.physics_interpolation_mode, Node.PHYSICS_INTERPOLATION_MODE_OFF,
		"y el motor no la atrasa un tick")


## La mirada se aplica en `_process`. Si la camara la tomara de la cadena
## interpolada por el motor llegaria hasta un tick tarde; tiene que ser la de ahora.
func test_the_view_turns_in_the_same_frame_as_the_look() -> void:
	_player._look_yaw += 90.0
	await wait_process_frames(2)
	var expected: Basis = (_rig.global_transform * _camera_local()).basis
	assert_true(_camera.global_basis.is_equal_approx(expected),
		"la camara mira a donde mira el jugador, sin esperar a la fisica")


## Las balas salen de la cabeza, no de la camara: interpolar el dibujo no puede
## mover un tiro.
func test_the_aim_still_comes_from_the_head() -> void:
	assert_eq(_player.get_aim_transform(), _player.head.global_transform)


func test_a_teleport_does_not_drag_the_camera_across_the_arena() -> void:
	_player.teleport_to(Vector3(30.0, 0.1, 30.0))
	await wait_process_frames(1)
	var expected: Vector3 = (_rig.global_transform * _camera_local()).origin
	assert_lt(_camera.global_position.distance_to(expected), 0.5,
		"la camara aparece donde aparecio el cuerpo, no a mitad de camino")


func _camera_local() -> Transform3D:
	return _player.view_interpolator._camera_local
