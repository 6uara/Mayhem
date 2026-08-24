extends GutTest
## El Ranged Flyer: el unico que no toca el piso.
##
## Volar no es un numero distinto, es un modo de movimiento entero
## (PLAN_NEW_ENEMY_TYPES §2.3): sin navmesh, sin gravedad, sin saltos y sin links.
## Lo que se prueba aca son las cuatro promesas de ese modo, que fallan todas en
## silencio:
##
##   1. Se mantiene a su altura **sobre el terreno**, no sobre el cero del arena.
##      Sobre una rampa que sube, sube.
##   2. No se cae. Ni por gravedad, ni al ser aturdido.
##   3. No se mete en el techo.
##   4. Llega por el costado, que es lo que lo hace distinto de un Ranger.
##
## Ninguna tira un error: un volador hundido en una rampa se ve como un bicho
## nadando en la geometria, y uno que se cae se ve como un Ranger lento.

const ENEMY_SCENE: String = "res://scenes/enemies/enemy.tscn"
const FLYER: String = "res://data/enemies/flyer.tres"
const RANGER: String = "res://data/enemies/ranger.tres"

var _spawned: Array[Enemy] = []
var _player: Node3D = null
var _ground: StaticBody3D = null


func before_each() -> void:
	_player = Node3D.new()
	_player.add_to_group(&"player")
	add_child(_player)
	_player.global_position = Vector3(30.0, 0.0, 0.0)


func after_each() -> void:
	for enemy: Enemy in _spawned:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_spawned.clear()
	for node: Node in [_player, _ground]:
		if is_instance_valid(node):
			node.queue_free()
	_player = null
	_ground = null
	ObjectPool.release_all()
	await wait_physics_frames(2)


## Un piso de verdad, porque el vuelo se mide con un rayo contra el mundo: sin
## nada abajo el arquetipo mantiene la altura que tiene, que es otra rama.
func _add_ground(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child_autofree(body)
	body.global_position = at
	return body


func _spawn(path: String, at: Vector3) -> Enemy:
	var enemy: Enemy = load(ENEMY_SCENE).instantiate()
	add_child(enemy)
	await wait_physics_frames(1)
	enemy.setup(load(path), at)
	await wait_physics_frames(1)
	_spawned.append(enemy)
	return enemy


func _data() -> EnemyData:
	return load(FLYER)


# --------------------------------------------------------------- el modo vuelo

func test_only_the_flyer_flies() -> void:
	var flyer: Enemy = await _spawn(FLYER, Vector3.ZERO)
	var ranger: Enemy = await _spawn(RANGER, Vector3(5.0, 0.0, 0.0))
	assert_true(flyer.is_flying())
	assert_false(ranger.is_flying(), "el resto del bestiario camina")


## Pooleado: el cuerpo vuelve como otra cosa y no puede quedarse volando.
func test_a_recycled_body_stops_flying() -> void:
	var enemy: Enemy = await _spawn(FLYER, Vector3.ZERO)
	assert_true(enemy.is_flying())
	enemy.setup(load(RANGER), Vector3.ZERO)
	await wait_physics_frames(1)
	assert_false(enemy.is_flying(), "reutilizado como Ranger: camina")


func test_it_climbs_to_its_altitude_over_the_ground() -> void:
	_add_ground(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
	var flyer: Enemy = await _spawn(FLYER, Vector3(0.0, 0.5, 0.0))
	await wait_seconds(2.5)
	assert_almost_eq(flyer.global_position.y, _data().flight_height, 1.0,
		"sube desde el piso hasta su altura de crucero")


## La promesa central: la altura es **sobre el terreno**. El mismo bicho, con el
## piso mas arriba, tiene que volar mas arriba.
func test_its_altitude_follows_the_terrain_under_it() -> void:
	_add_ground(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0))
	var low: Enemy = await _spawn(FLYER, Vector3(0.0, 0.5, 0.0))
	await wait_seconds(2.5)
	var low_altitude: float = low.global_position.y

	_add_ground(Vector3(60.0, 5.5, 0.0), Vector3(20.0, 1.0, 20.0))
	var high: Enemy = await _spawn(FLYER, Vector3(60.0, 6.5, 0.0))
	await wait_seconds(2.5)

	assert_almost_eq(high.global_position.y - low_altitude, 6.0, 1.2,
		"seis metros mas de terreno son seis metros mas de vuelo")


func test_gravity_never_touches_it() -> void:
	_add_ground(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
	var flyer: Enemy = await _spawn(FLYER, Vector3(0.0, 5.0, 0.0))
	await wait_seconds(1.5)
	assert_gt(flyer.global_position.y, 2.0, "no se cayo")


## Aturdirlo lo frena, no lo baja. Si el aturdimiento le apagara la altura, cada
## impacto lo tiraria al piso y el arquetipo dejaria de ser un arquetipo.
func test_stunning_it_does_not_drop_it() -> void:
	_add_ground(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
	var flyer: Enemy = await _spawn(FLYER, Vector3(0.0, 5.0, 0.0))
	await wait_seconds(1.0)
	var before: float = flyer.global_position.y

	flyer.apply_stun(2.0)
	await wait_seconds(1.0)
	assert_almost_eq(flyer.global_position.y, before, 1.0, "aturdido y en el aire")


## Debajo de una galeria, un volador que insiste en su altura de crucero se queda
## apretado contra el techo temblando. Lo que corresponde es volar mas bajo.
func test_a_ceiling_pushes_it_down_instead_of_squeezing_it() -> void:
	_add_ground(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
	_add_ground(Vector3(0.0, 3.0, 0.0), Vector3(40.0, 1.0, 40.0))
	var flyer: Enemy = await _spawn(FLYER, Vector3(0.0, 0.5, 0.0))
	await wait_seconds(2.5)

	assert_lt(flyer.global_position.y, 2.5, "se quedo abajo del techo")
	assert_gt(flyer.global_position.y, 0.0, "y no se hundio en el piso")


# ------------------------------------------------------------------ el arquetipo

## §4.1: ataca desde los costados y arranca fuera del campo de vision. Con el FOV
## por defecto en 104 grados (o sea +-52), un rumbo de 90 cae holgadamente afuera.
func test_it_comes_from_the_side_and_not_from_the_front() -> void:
	assert_almost_eq(_data().approach_bearing_degrees, 90.0, 0.01)
	assert_true(_data().approach_bearing_mirrors, "por los dos costados")
	assert_gt(_data().approach_bearing_weight, 0.0, "el rumbo tiene que pesar algo")


func test_its_approach_point_is_off_to_one_side() -> void:
	_add_ground(Vector3(0.0, -0.5, 0.0), Vector3(80.0, 1.0, 80.0))
	# El jugador mirando hacia -Z, que es el frente en Godot.
	_player.global_position = Vector3.ZERO
	_player.look_at(Vector3(0.0, 0.0, -10.0), Vector3.UP)
	var flyer: Enemy = await _spawn(FLYER, Vector3(0.0, 5.0, 25.0))

	var approach: Vector3 = flyer.get_approach_position()
	assert_gt(absf(approach.x), 1.0,
		"el punto de aproximacion se corre a un costado del jugador")


func test_it_does_not_jump() -> void:
	assert_false(_data().can_jump,
		"un volador que saltara estaria peleando contra su propio modo de moverse")


# ----------------------------------------------------- la ventana de compromiso

## Sin esto el arquetipo no hace ninguna pregunta: flota a 13m, tira cada 2.6s y
## se resuelve por acumulacion. La picada es el momento en el que matarlo se
## siente bien, y es lo unico que separa a un volador de un peaje.
func test_the_dive_brings_it_down_to_where_the_shotgun_lives() -> void:
	_add_ground(Vector3(0.0, -0.5, 0.0), Vector3(200.0, 1.0, 200.0))
	var flyer: Enemy = await _spawn(FLYER, Vector3.ZERO)
	var dive := ActionFlyerDive.new()
	dive.dive_height = 2.5
	add_child_autofree(dive)
	var blackboard := Blackboard.new()
	add_child_autofree(blackboard)

	assert_almost_eq(flyer.get_flight_height(), _data().flight_height, 0.01,
		"antes de la picada vuela a su altura de crucero")
	dive.before_run(flyer, blackboard)
	assert_almost_eq(flyer.get_flight_height(), 2.5, 0.01, "durante la picada, baja")


## Y vuelve a subir. Un Flyer que se queda con la altura de picada pisada es un
## Flyer que no vuelve a volar nunca, y eso no falla: se ve como que el arquetipo
## era otro.
func test_the_dive_always_gives_the_altitude_back() -> void:
	_add_ground(Vector3(0.0, -0.5, 0.0), Vector3(200.0, 1.0, 200.0))
	var flyer: Enemy = await _spawn(FLYER, Vector3.ZERO)
	var dive := ActionFlyerDive.new()
	dive.dive_height = 2.5
	add_child_autofree(dive)
	var blackboard := Blackboard.new()
	add_child_autofree(blackboard)

	dive.before_run(flyer, blackboard)
	dive.interrupt(flyer, blackboard)
	assert_almost_eq(flyer.get_flight_height(), _data().flight_height, 0.01,
		"cortada a la mitad, la altura vuelve igual")


## El reloj de la picada no puede vivir adentro de la picada: la secuencia
## reactiva vuelve a preguntar la condicion en cada frame mientras la accion
## corre, asi que si la condicion se rearmara sola la picada se cortaria en el
## frame siguiente al que empieza.
func test_the_dive_clock_is_rearmed_by_the_dive_and_not_by_itself() -> void:
	_add_ground(Vector3(0.0, -0.5, 0.0), Vector3(200.0, 1.0, 200.0))
	var flyer: Enemy = await _spawn(FLYER, Vector3.ZERO)
	var ready := ConditionDiveReady.new()
	ready.interval = 8.0
	add_child_autofree(ready)
	var blackboard := Blackboard.new()
	add_child_autofree(blackboard)

	blackboard.set_value(ConditionDiveReady.COOLDOWN_KEY, 0.0)
	assert_eq(ready.tick(flyer, blackboard), BeehaveNode.SUCCESS, "con el reloj en cero, toca")
	assert_eq(ready.tick(flyer, blackboard), BeehaveNode.SUCCESS,
		"y sigue tocando mientras la picada corre, o se cortaria sola")

	var dive := ActionFlyerDive.new()
	add_child_autofree(dive)
	dive._finish(flyer, blackboard)
	assert_eq(ready.tick(flyer, blackboard), BeehaveNode.FAILURE,
		"terminada la picada, el reloj arranca de nuevo")


# ------------------------------------------------------ nunca sobre el vacio

## Un volador sobre un pozo esta fuera del alcance de media mitad del arsenal. No
## es dificultad: es que la respuesta del jugador deja de existir.
func test_it_will_not_park_itself_over_a_hole() -> void:
	# Una isla de piso, y el resto del mundo vacio.
	_add_ground(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0))
	_player.global_position = Vector3.ZERO
	var flyer: Enemy = await _spawn(FLYER, Vector3(2.0, 5.0, 0.0))

	flyer.set_move_target(Vector3(60.0, 5.0, 0.0))
	assert_lt(flyer.move_target.x, 11.0,
		"el destino se acerca hasta tener piso debajo, en vez de quedar sobre el vacio")
	assert_true(flyer.has_ground_below(flyer.move_target), "y el punto final tiene piso")


## Pero si el punto ya tiene piso, no se toca. El clamp es una red, no un iman.
func test_a_destination_with_ground_under_it_is_left_alone() -> void:
	_add_ground(Vector3(0.0, -0.5, 0.0), Vector3(200.0, 1.0, 200.0))
	var flyer: Enemy = await _spawn(FLYER, Vector3.ZERO)
	var wanted := Vector3(14.0, 5.0, 3.0)
	flyer.set_move_target(wanted)
	assert_almost_eq(flyer.move_target.distance_to(wanted), 0.0, 0.01,
		"sobre piso firme, el destino queda donde estaba")
