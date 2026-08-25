extends GutTest
## De dónde viene cada arquetipo, medido desde hacia dónde mira el jugador.
##
## El problema que esto resuelve no es cuántos enemigos hay sino dónde están. Si
## todos llegan de frente, la ola se resuelve girando lo menos posible y el arena
## deja de importar: no hay que chequear la espalda, no hay que reposicionarse, y
## dos arquetipos distintos se sienten iguales porque ocupan el mismo sector.
##
## `EnemyData.approach_bearing_weight` en 0 deja el comportamiento exactamente
## como estaba, y por eso es el default: los cinco arquetipos originales no se
## enteran de que este sistema existe. Eso también se prueba acá.

const ENEMY_SCENE: String = "res://scenes/enemies/enemy.tscn"
const BOMBER: String = "res://data/enemies/bomber.tres"
const ENVIRONMENTAL: String = "res://data/enemies/environmental.tres"
const RUSHER: String = "res://data/enemies/rusher.tres"

var _player: Node3D


## Un jugador falso: lo único que el sistema le pide es una posición y un basis.
## Se para mirando hacia -Z, que es el frente en Godot, así que "detrás" es +Z y
## los flancos son +-X. Eso hace legibles todas las aserciones de abajo.
func before_each() -> void:
	_player = Node3D.new()
	_player.add_to_group(&"player")
	add_child_autofree(_player)
	_player.global_position = Vector3.ZERO
	_player.rotation = Vector3.ZERO
	await wait_physics_frames(1)


func after_each() -> void:
	ObjectPool.release_all()
	await wait_physics_frames(1)


func _spawn(path: String, at: Vector3) -> Enemy:
	var enemy: Enemy = load(ENEMY_SCENE).instantiate()
	add_child_autofree(enemy)
	await wait_physics_frames(1)
	enemy.setup(load(path), at)
	await wait_physics_frames(1)
	return enemy


# ------------------------------------------------------- el Bomber, por detrás

## Lo pedido: la bomba se acerca por la espalda. Se la para justo en la cara del
## jugador, que es el peor caso, y el punto al que quiere caminar tiene que estar
## del otro lado.
func test_the_bomber_routes_around_to_the_players_back() -> void:
	var bomber: Enemy = await _spawn(BOMBER, Vector3(0.0, 0.0, -20.0))
	var approach: Vector3 = bomber.get_approach_position()
	assert_gt(approach.z, 0.5,
		"el jugador mira a -Z, asi que la bomba tiene que apuntar a +Z (detras)")


## Y sigue siendo la espalda cuando el jugador gira: el rumbo se mide desde su
## mirada, no desde una dirección fija del arena. Sin esto "por atrás" sería
## "por el norte", que no es lo mismo en absoluto.
func test_behind_is_measured_from_where_the_player_looks() -> void:
	_player.rotation.y = deg_to_rad(90.0)
	await wait_physics_frames(1)
	# Mirando con yaw 90, el frente pasa a ser -X, asi que la espalda es +X.
	var bomber: Enemy = await _spawn(BOMBER, Vector3(-20.0, 0.0, 0.0))
	var approach: Vector3 = bomber.get_approach_position()
	assert_gt(approach.x, 0.5, "el jugador giro, la espalda giro con el")


## De cerca deja de insistir. Una bomba que persigue la espalda mientras el
## jugador gira se queda orbitando y no explota nunca: flanquea de lejos y se
## compromete de cerca, con la misma rampa que ya usaba el carril lateral.
func test_up_close_it_stops_circling_and_commits() -> void:
	var bomber: Enemy = await _spawn(BOMBER, Vector3(0.0, 0.0, -1.5))
	var approach: Vector3 = bomber.get_approach_position()
	assert_almost_eq(approach.distance_to(_player.global_position), 0.0, 0.6,
		"pegado al jugador, va derecho a el y no a rodearlo")


## Y sigue rodeando en la distancia a la que arma la espoleta. Antes commiteaba
## justo ahi (`fuse_arm_range`, 6m) para que el anillo se viera de frente, y el
## resultado era que toda la parte visible de la aproximacion venia de cara: el
## Bomber se leia como un Rusher lento. Arma por atras, que es lo que el
## arquetipo pide.
func test_it_still_flanks_at_fuse_arming_range() -> void:
	var bomber: Enemy = await _spawn(BOMBER, Vector3(0.0, 0.0, -6.0))
	var approach: Vector3 = bomber.get_approach_position()
	assert_gt(approach.z, 0.5,
		"a la distancia de armado todavia apunta a la espalda (+Z)")


# ------------------------------------------------ el Environmental, por el lado

## No de frente y no exactamente detrás: a un costado, que es desde donde un tiro
## en parábola cruza el camino del jugador en vez de venir por él.
func test_the_environmental_works_from_an_angle() -> void:
	var env: Enemy = await _spawn(ENVIRONMENTAL, Vector3(0.0, 0.0, -30.0))
	var approach: Vector3 = env.get_approach_position()
	# Que el punto no sea el jugador mismo, primero. Sin esta línea el test pasaba
	# vacío: `approach == target` da un vector nulo, `normalized()` lo deja nulo,
	# el `dot` da 0 y el ángulo da 90 grados exactos - o sea que "se sale del
	# frente" se cumplía justamente cuando el enemigo iba derecho al jugador. Fue
	# lo que dejó pasar que el commit se comía el rumbo entero (ver
	# `_approach_commit_distance()`).
	assert_gt(approach.distance_to(_player.global_position), 1.0,
		"el punto de aproximacion no puede ser el jugador mismo")
	var to_approach: Vector3 = (approach - _player.global_position).normalized()
	var facing: Vector3 = -_player.global_transform.basis.z
	var degrees: float = rad_to_deg(acos(clampf(to_approach.dot(facing), -1.0, 1.0)))
	assert_gt(degrees, 25.0, "se sale del frente del jugador")


# ------------------------------------------------------- los cinco de siempre

## La red de seguridad de todo el cambio. Un arquetipo con peso 0 tiene que dar
## exactamente el mismo punto que antes de que el sistema existiera: cerca del
## jugador, corrido a lo sumo por su carril lateral. Si esto se rompe, se
## rompieron los cinco arquetipos originales de una sola vez.
func test_an_archetype_without_a_bearing_is_untouched() -> void:
	var rusher: Enemy = await _spawn(RUSHER, Vector3(0.0, 0.0, -20.0))
	assert_eq(rusher.data.approach_bearing_weight, 0.0, "el Rusher no pide rumbo")
	var approach: Vector3 = rusher.get_approach_position()
	var sideways: float = absf(approach.x - _player.global_position.x)
	assert_lt(sideways, Enemy.APPROACH_SPREAD + 0.01,
		"solo el carril lateral de siempre, nada de rodear")
	assert_almost_eq(approach.z, _player.global_position.z, 0.01,
		"y no se corre ni adelante ni atras del jugador")


# --------------------------------------------------- adelantarse al movimiento

## El frasco va a donde el jugador VA a estar. Tirarle a donde está parado es
## tirarle a la espalda: para cuando el frasco aterriza ya se movió, y el charco
## queda negando terreno que acababa de dejar.
func test_the_flask_leads_a_moving_player() -> void:
	var throw := ActionThrowFlask.new()
	throw.flight_time = 1.0
	throw.lead_fraction = 0.65
	add_child_autofree(throw)

	var env: Enemy = await _spawn(ENVIRONMENTAL, Vector3(0.0, 0.0, -15.0))
	var standing: Vector3 = throw._predicted_spot(env)
	assert_almost_eq(standing.distance_to(_player.global_position), 0.0, 0.01,
		"un jugador quieto no necesita adelanto")

	# El jugador falso no es un CharacterBody3D, asi que no tiene velocidad: se
	# comprueba con uno que si lo sea.
	_player.queue_free()
	var runner := CharacterBody3D.new()
	runner.add_to_group(&"player")
	add_child_autofree(runner)
	await wait_physics_frames(1)
	runner.velocity = Vector3(6.0, 0.0, 0.0)
	var moving: Enemy = await _spawn(ENVIRONMENTAL, Vector3(0.0, 0.0, -15.0))
	var predicted: Vector3 = throw._predicted_spot(moving)
	assert_almost_eq(predicted.x, 6.0 * 1.0 * 0.65, 0.01,
		"cae adelante del jugador, en el camino")


## Un jugador saltando no recibe el charco por encima ni por debajo del piso: el
## charco vive en el suelo, asi que solo se adelanta la parte horizontal.
func test_the_lead_ignores_vertical_speed() -> void:
	var throw := ActionThrowFlask.new()
	throw.flight_time = 1.0
	throw.lead_fraction = 1.0
	add_child_autofree(throw)

	_player.queue_free()
	var jumper := CharacterBody3D.new()
	jumper.add_to_group(&"player")
	add_child_autofree(jumper)
	await wait_physics_frames(1)
	jumper.velocity = Vector3(0.0, 12.0, 0.0)
	var env: Enemy = await _spawn(ENVIRONMENTAL, Vector3(0.0, 0.0, -15.0))
	assert_almost_eq(throw._predicted_spot(env).y, jumper.global_position.y, 0.01,
		"saltar no manda el charco al aire")
