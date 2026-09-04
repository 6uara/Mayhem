extends GutTest
## El gadget tiene que terminar en el piso de la arena, no contra la pared.
##
## Este test existe por un bug que ningun test unitario podia ver: el venue pone
## un muro invisible de 14 metros entre las gradas y el area de juego -es lo que
## impide que el jugador se caiga al foso- y el gadget salia de un asiento que
## esta afuera y a un metro de altura. Cada tiro se estrellaba contra la cara de
## afuera del muro y se quedaba ahi, en el foso, donde nadie lo puede levantar.
##
## Los tests del director aprobaban igual porque miran el punto al que se apunta,
## no adonde se llega. Esto vuela el arco de verdad, con el muro puesto.

const DROP_SCENE: String = "res://scenes/arena/crowd_drop_pickup.tscn"
const PLAYER_SCENE: String = "res://scenes/player/player.tscn"
const TABLE_PATH: String = "res://data/crowd_drop_table.tres"

## Copia de lo que arman los dos shells: media arena, y el muro justo en el borde.
const ARENA_HALF: float = 30.0
const WALL_HEIGHT: float = 14.0
const WALL_THICKNESS: float = 2.0

var _floor: StaticBody3D


func before_each() -> void:
	_build_venue()


func after_each() -> void:
	ObjectPool.release_all()


## El piso de la arena y los cuatro muros del perimetro, en la capa WORLD, que es
## contra lo que el gadget resuelve su arco.
func _build_venue() -> void:
	_floor = _box(Vector3(ARENA_HALF * 2.0, 1.0, ARENA_HALF * 2.0), Vector3(0.0, -0.5, 0.0))
	var offsets: Array[Vector3] = [
		Vector3(0.0, 0.0, -ARENA_HALF - WALL_THICKNESS * 0.5),
		Vector3(0.0, 0.0, ARENA_HALF + WALL_THICKNESS * 0.5),
		Vector3(-ARENA_HALF - WALL_THICKNESS * 0.5, 0.0, 0.0),
		Vector3(ARENA_HALF + WALL_THICKNESS * 0.5, 0.0, 0.0),
	]
	for offset: Vector3 in offsets:
		var size := Vector3(ARENA_HALF * 2.0, WALL_HEIGHT, WALL_THICKNESS)
		if is_zero_approx(offset.z):
			size = Vector3(WALL_THICKNESS, WALL_HEIGHT, ARENA_HALF * 2.0)
		_box(size, offset + Vector3(0.0, WALL_HEIGHT * 0.5, 0.0))


func _box(size: Vector3, position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	body.position = position
	add_child_autofree(body)
	return body


func _director() -> CrowdDropDirector:
	var director := CrowdDropDirector.new()
	director.table = (load(TABLE_PATH) as CrowdDropTable).duplicate() as CrowdDropTable
	director.drop_scene = load(DROP_SCENE) as PackedScene
	add_child_autofree(director)
	return director


## Un asiento como el que sembraria CrowdStands en la primera fila: afuera del
## muro, casi a ras del piso.
func _seat_crowd() -> CrowdStands:
	var crowd := CrowdStands.new()
	add_child_autofree(crowd)
	crowd.populate(
		AABB(Vector3(-ARENA_HALF, 0.0, -ARENA_HALF),
			Vector3(ARENA_HALF * 2.0, 6.0, ARENA_HALF * 2.0)), 4.0)
	return crowd


func test_the_gadget_clears_the_barrier_and_lands_inside() -> void:
	var player: Player = add_child_autofree(load(PLAYER_SCENE).instantiate()) as Player
	player.global_position = Vector3(0.0, 1.0, 0.0)
	_seat_crowd()
	var director: CrowdDropDirector = _director()
	await wait_physics_frames(2)

	for attempt: int in 8:
		var pickup: CrowdDropPickup = director.throw_now()
		assert_not_null(pickup)
		# Se le da todo el vuelo mas un margen: si choco el muro aterriza mucho
		# antes, y el sitio donde quedo es lo que delata el problema.
		await wait_physics_frames(int(director.flight_time * 70.0))

		assert_true(pickup.is_available,
			"el gadget %d nunca aterrizo" % attempt)
		var landed: Vector3 = pickup.global_position
		assert_lt(absf(landed.x), ARENA_HALF,
			"el gadget %d quedo fuera de la arena en x (%v)" % [attempt, landed])
		assert_lt(absf(landed.z), ARENA_HALF,
			"el gadget %d quedo fuera de la arena en z (%v)" % [attempt, landed])
		assert_lt(landed.y, 3.0,
			"el gadget %d quedo colgado del muro en vez de tocar el piso (%v)"
				% [attempt, landed])
		ObjectPool.release(pickup)
