extends GutTest
## La caja de municion se levanta estando encima, no solo al entrar.

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const BOX_SCENE: PackedScene = preload("res://scenes/arena/ammo_pickup.tscn")

var _player: Player
var _box: AmmoPickup


func before_each() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	add_child_autofree(floor_body)

	_player = add_child_autofree(PLAYER_SCENE.instantiate())
	_player.global_position = Vector3(0, 0.1, 0)
	_box = add_child_autofree(BOX_SCENE.instantiate())
	_box.global_position = Vector3(0, 0.5, 0)
	await wait_physics_frames(6)


## Entrar con la reserva llena la deja ahi, a proposito. Pero quien se queda
## parado encima y gasta balas tiene que poder levantarla sin salir y volver a
## entrar: body_entered ya no vuelve a avisar.
func test_standing_on_the_box_takes_it_once_there_is_room() -> void:
	var weapon: WeaponComponent = _player.weapon
	assert_true(_box.is_available, "con la reserva llena la caja se queda")

	weapon._reserve = 0
	await wait_physics_frames(4)

	assert_false(_box.is_available, "con lugar en la reserva, la levanta parado encima")
	assert_gt(weapon.get_reserve(), 0, "y la reserva se lleno un poco")
