extends GutTest
## Los atascos que ninguna de las salidas de `test_enemy_obstacles.gd` atiende.
##
## Aquellas prueban el atasco con forma de obstaculo: una cornisa se pisa, un muro
## bajo se salta. Estas son las otras formas que se vieron en partida y que no
## tenian salida ninguna - el jugador arriba de algo a lo que no se llega
## caminando, el atasco que no tiene forma de nada saltable, y el tirador plantado
## detras de una columna disparandole a la columna.

const ARENA: String = "res://scenes/arena/greybox_arena.tscn"
const ENEMY_SCENE: String = "res://scenes/enemies/enemy.tscn"

var _arena: Node3D = null
var _player: Node3D = null


func before_each() -> void:
	_arena = load(ARENA).instantiate()
	add_child_autofree(_arena)
	await wait_physics_frames(4)
	NavigationServer3D.map_force_update(_map())
	_player = Node3D.new()
	_player.add_to_group(&"player")
	add_child_autofree(_player)


func _map() -> RID:
	return (_arena.get_node("Navigation") as NavigationRegion3D).get_navigation_map()


## Un punto del piso jugable, para no escribir alturas a mano.
func _on_floor_at(x: float, z: float) -> Vector3:
	return NavigationServer3D.map_get_closest_point(_map(), Vector3(x, 1.0, z))


func _off_mesh_by(point: Vector3) -> float:
	var closest: Vector3 = NavigationServer3D.map_get_closest_point(_map(), point)
	return Vector2(point.x - closest.x, point.z - closest.z).length()


## Una caja solida puesta en tiempo de ejecucion. El navmesh esta bakeado en disco,
## asi que lo que se agrega ahora es geometria sin navegacion - o sea exactamente
## la plataforma a la que un enemigo no puede subir.
func _make_box(box_size: Vector3, position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	body.add_child(shape)
	add_child_autofree(body)
	body.global_position = position
	return body


func _spawn(archetype: String, at: Vector3) -> Enemy:
	var enemy: Enemy = load(ENEMY_SCENE).instantiate()
	add_child_autofree(enemy)
	await wait_physics_frames(1)
	enemy.setup(load("res://data/enemies/%s.tres" % archetype), at)
	await wait_physics_frames(1)
	return enemy


# ------------------------------------------------------- llegar no es atascarse

## La confusion que estaba abajo de casi todo lo demas. Un enemigo que llego a su
## destino se queda quieto con `is_moving` todavia en true hasta que la hoja del
## arbol le de la proxima orden, y eso se leia igual que estar trabado: quieto y
## con orden de moverse. Si ademas tenia una pared al lado, se la saltaba.
func test_an_enemy_that_arrived_is_not_treated_as_stuck() -> void:
	_player.global_position = _on_floor_at(0.0, 0.0)
	var enemy: Enemy = await _spawn("rusher", _on_floor_at(0.0, 2.0))
	enemy.set_move_target(enemy.global_position)

	await wait_physics_frames(2)
	assert_true(enemy._has_arrived(), "el camino se termino")
	enemy._stuck_time = 0.0
	await wait_seconds(1.0)

	assert_eq(enemy._stuck_time, 0.0,
		"llegar al destino no puede contar como estar atascado")


# ------------------------------------------- el jugador arriba de una plataforma

## El caso que rompia la partida. Antes se frenaba dejando `is_moving` en true, o
## sea leido como atascado, y el enemigo se pasaba la ola saltando en el lugar cada
## tres segundos contra la pared de la plataforma.
func test_an_unreachable_target_is_admitted_instead_of_ground_against() -> void:
	var base: Vector3 = _on_floor_at(0.0, 0.0)
	_make_box(Vector3(6, 6, 6), base + Vector3.UP * 3.0)
	_player.global_position = base + Vector3.UP * 6.5
	var enemy: Enemy = await _spawn("rusher", _on_floor_at(0.0, 9.0))

	enemy.set_move_target(_player.global_position)
	await wait_seconds(2.0)

	assert_true(enemy.is_target_unreachable(),
		"el navmesh ya dijo que no llega; el enemigo tiene que haberse enterado")
	# Y lo que hace con eso es irse caminando a donde si puede llegar - por el
	# camino que el navmesh le da, links incluidos. Lo que no hace es quedarse
	# empujando la plataforma: nada de estar atascado, nada de saltos fallidos.
	assert_eq(enemy._stuck_time, 0.0, "no se quedo empujando contra la plataforma")
	assert_eq(enemy._detour_time, 0.0, "y no hubo ningun salto fallido que rodear")


## Rendirse no es quedarse clavado donde estaba: se camina hasta lo mas cerca que
## se puede llegar. Un enemigo esperando al pie de la plataforma se lee como que
## esta esperando; uno clavado a diez metros se lee como que se rompio.
func test_the_closest_reachable_point_is_walkable_and_closer() -> void:
	var base: Vector3 = _on_floor_at(0.0, 0.0)
	_make_box(Vector3(6, 6, 6), base + Vector3.UP * 3.0)
	_player.global_position = base + Vector3.UP * 6.5
	var enemy: Enemy = await _spawn("rusher", _on_floor_at(0.0, 12.0))

	var reachable: Vector3 = enemy.closest_reachable_point(_player.global_position)
	assert_lt(_off_mesh_by(reachable), 1.0, "el punto al que se rinde es piso navegable")
	assert_lt(Vector2(reachable.x - _player.global_position.x,
		reachable.z - _player.global_position.z).length(),
		Vector2(enemy.global_position.x - _player.global_position.x,
			enemy.global_position.z - _player.global_position.z).length(),
		"y esta mas cerca del jugador que el punto de partida")


## Y la hoja de perseguir lo usa: con el objetivo declarado inalcanzable, el
## destino deja de ser el carril de aproximacion -que cae en la otra isla- y pasa a
## ser el punto al que se llega de verdad.
func test_chase_walks_to_the_reachable_point_when_the_target_is_unreachable() -> void:
	var base: Vector3 = _on_floor_at(0.0, 0.0)
	_make_box(Vector3(6, 6, 6), base + Vector3.UP * 3.0)
	_player.global_position = base + Vector3.UP * 6.5
	var enemy: Enemy = await _spawn("rusher", _on_floor_at(0.0, 12.0))
	enemy._target_unreachable = true

	var chase := ActionChasePlayer.new()
	add_child_autofree(chase)
	chase.before_run(enemy, Blackboard.new())
	assert_eq(chase.tick(enemy, Blackboard.new()), BeehaveNode.RUNNING,
		"sigue siendo lo que esta haciendo")
	assert_lt(_off_mesh_by(enemy.move_target), 1.0,
		"pero camina a un punto que existe, no a la plataforma")


# ------------------------------------------------------ el destrabe por reloj

## El ultimo escalon. Cuando el atasco no tiene forma de nada saltable ni pisable,
## el reloj lo saca igual: sin esto el enemigo se queda ahi el resto de la ola.
func test_a_long_stall_forces_the_enemy_out() -> void:
	_player.global_position = _on_floor_at(0.0, -6.0)
	var enemy: Enemy = await _spawn("rusher", _on_floor_at(0.0, 6.0))
	var origin: Vector3 = enemy.global_position
	var before: float = enemy.global_position.distance_to(_player.global_position)

	enemy._stuck_time = Enemy.STUCK_WARP_TIME
	enemy._force_unstick()

	assert_eq(enemy._stuck_time, 0.0, "el reloj arranca de nuevo")
	assert_gt(enemy._detour_time, 0.0, "y sale rodeando, no de frente contra lo mismo")
	assert_lte(enemy.global_position.distance_to(_player.global_position), before,
		"el empujon va hacia el objetivo, no a cualquier lado")
	assert_lt(enemy.global_position.distance_to(origin),
		Enemy.WARP_SAMPLES * Enemy.WARP_STEP + 1.0,
		"y es corto: un enemigo que aparece lejos es peor bug que el que arregla")
	assert_lt(_off_mesh_by(enemy.global_position), 1.0,
		"termina parado en piso navegable, o el destrabe seria el proximo atasco")


## El salto sigue siendo la primera respuesta: destrabar por reloj es el ultimo
## recurso y no puede adelantarsele, o los enemigos dejarian de saltar cosas.
func test_the_clock_does_not_beat_the_jump() -> void:
	assert_gt(Enemy.STUCK_WARP_TIME, Enemy.STUCK_TIME,
		"primero el salto, despues el reloj")
	assert_gt(Enemy.STUCK_WARP_TIME, Enemy.FAILED_JUMP_COOLDOWN,
		"y con margen para que un salto fallido llegue a cobrarse su castigo")


# --------------------------------------------------------------- los links

func _make_link(from: Vector3, to: Vector3) -> JumpLink:
	var link := JumpLink.new()
	add_child_autofree(link)
	link.global_position = Vector3.ZERO
	link.start_position = from
	link.end_position = to
	return link


## Dos links contiguos que fallan uno detras del otro. Con un solo slot de
## bloqueo, el segundo borraba al primero y el enemigo alternaba entre los dos
## para siempre: el mismo pogo que el bloqueo existe para cortar.
func test_two_links_can_be_blocked_at_once() -> void:
	var enemy: Enemy = await _spawn("rusher", _on_floor_at(0.0, 0.0))
	var first: JumpLink = _make_link(enemy.global_position, enemy.global_position + Vector3.FORWARD * 4.0)
	var second: JumpLink = _make_link(enemy.global_position, enemy.global_position + Vector3.RIGHT * 4.0)

	enemy._last_link = first
	enemy._note_jump_result(0.0)
	enemy._last_link = second
	enemy._note_jump_result(0.0)

	assert_true(enemy._blocked_links.has(first), "el primero sigue bloqueado")
	assert_true(enemy._blocked_links.has(second), "y el segundo tambien")


## Y el bloqueo vence solo, o un arena entera se quedaria sin links cruzables
## despues de un par de saltos mal salidos.
func test_a_blocked_link_comes_back() -> void:
	var enemy: Enemy = await _spawn("rusher", _on_floor_at(0.0, 0.0))
	var link: JumpLink = _make_link(enemy.global_position, enemy.global_position + Vector3.FORWARD * 4.0)
	enemy._last_link = link
	enemy._note_jump_result(0.0)

	enemy._expire_blocked_links(Enemy.LINK_BLOCK_TIME + 0.1)
	assert_false(enemy._blocked_links.has(link), "cumplido el castigo, vuelve a la mesa")


## El destino que ve `_find_link_ahead()` es el ya corregido por
## `navigable_position()`, que puede haberlo acercado a **este** lado del hueco: la
## cuenta de distancias dice entonces que cruzar es un rodeo, y el enemigo rechaza
## el unico link que su propio camino le pide tomar. El camino manda.
func test_a_link_the_path_routes_through_is_taken_even_if_it_looks_like_a_detour() -> void:
	var enemy: Enemy = await _spawn("rusher", _on_floor_at(0.0, 0.0))
	enemy.set_move_target(_on_floor_at(0.0, -14.0))
	await wait_physics_frames(2)
	var next_point: Vector3 = enemy.agent.get_next_path_position()

	var link: JumpLink = _make_link(enemy.global_position, next_point)
	enemy._cache_links()
	# El caso: el destino quedo corregido a los pies del enemigo, asi que cualquier
	# salida esta "mas lejos del destino" que el propio enemigo.
	enemy.move_target = enemy.global_position

	assert_true(enemy._path_routes_through(link.get_exit_for(enemy.global_position)),
		"el camino pasa por la salida del link")
	assert_eq(enemy._find_link_ahead(), link,
		"asi que se cruza, aunque la cuenta de distancias lo llame rodeo")


# ------------------------------------------------------- el salto sin aterrizaje

## Un salto que no aterriza nunca -se cayo del arena, lo empujaron- dejaba la
## marca puesta, y el proximo aterrizaje de este cuerpo se juzgaba contra un
## origen viejo: un salto bueno cobrando el castigo de otro.
func test_a_jump_that_never_lands_is_forgotten_instead_of_charged() -> void:
	var enemy: Enemy = await _spawn("rusher", _on_floor_at(0.0, 0.0))
	enemy._begin_jump()
	enemy._judge_landing(Enemy.JUMP_PENDING_TIMEOUT + 0.1)
	assert_false(enemy._jump_pending, "se dejo de esperar ese aterrizaje")

	# Y el proximo aterrizaje de verdad no se cobra contra aquel origen.
	enemy._was_on_floor = false
	enemy._judge_landing(0.016)
	assert_eq(enemy._jump_cooldown_left, 0.0, "sin castigo heredado")
	assert_eq(enemy._detour_time, 0.0, "y sin rodeo heredado")


## El salto de ataque no es un salto de navegacion. Se lo juzgaba con la vara de
## cuanto terreno cubrio, y un salto encima de alguien que esta a un metro cubre
## menos que el minimo: el ataque que acerto se registraba como salto fallido y se
## cobraba tres segundos sin saltar mas un rodeo.
func test_an_attack_leap_is_not_judged_as_a_failed_jump() -> void:
	_player.global_position = _on_floor_at(0.0, -1.0) + Vector3.UP * 0.5
	var enemy: Enemy = await _spawn("rusher", _on_floor_at(0.0, 0.0))
	# Apoyado en el piso: un salto solo sale desde el piso, y un cuerpo recien
	# spawneado tarda un par de frames en terminar de caer.
	await wait_seconds(0.5)
	assert_true(enemy.is_on_floor(), "esta parado")

	assert_true(enemy.start_leap(), "el salto sale")
	assert_false(enemy._jump_pending, "pero no entra en la contabilidad de navegacion")

	await wait_seconds(1.5)
	assert_eq(enemy._jump_cooldown_left, 0.0,
		"y aterrizar encima del jugador no cuesta el castigo de un salto fallido")


# ------------------------------------------------------------ el volador

## Un volador no salta ni pisa escalones, asi que ninguna de las salidas de a pie
## le sirve: su unica respuesta a algo adelante era subir. Bajo un techo eso no
## alcanza -el techo lo empuja para abajo y la pared para arriba- y se quedaba
## temblando contra el rincon. Pasado un tiempo bloqueado, sale por el costado.
func test_a_blocked_flyer_eventually_goes_around() -> void:
	var base: Vector3 = _on_floor_at(0.0, 0.0)
	var flyer: Enemy = await _spawn("flyer", base + Vector3(0.0, 5.0, 6.0))
	# Pared alta justo delante, y techo encima: subir deja de ser una salida.
	_make_box(Vector3(12, 20, 1), base + Vector3(0.0, 10.0, 3.0))
	_make_box(Vector3(12, 1, 12), base + Vector3(0.0, 7.0, 6.0))
	flyer.set_move_target(base + Vector3(0.0, 5.0, -6.0))
	await wait_physics_frames(1)

	assert_eq(flyer._detour_time, 0.0, "todavia no: subir es la primera respuesta")
	for i: int in 40:
		flyer._fly(0.05)
	assert_gt(flyer._detour_time, 0.0,
		"con la pared adelante y el techo arriba tiene que probar por el costado")


# ------------------------------------------------------ disparar a una columna

## El tirador detras de una pared. La distancia sola abria la rama de disparo, y
## `ActionKeepDistance` devolvia SUCCESS porque estaba a la distancia que queria:
## el selector no llegaba nunca a moverlo y se quedaba tirandole a la columna.
func test_a_ranged_enemy_does_not_open_its_shoot_branch_through_a_wall() -> void:
	var base: Vector3 = _on_floor_at(0.0, 0.0)
	_make_box(Vector3(10, 6, 1), base + Vector3.UP * 3.0)
	_player.global_position = base + Vector3(0.0, 0.5, -5.0)
	var enemy: Enemy = await _spawn("ranger", base + Vector3(0.0, 0.0, 5.0))

	assert_false(enemy.has_line_of_sight_to_target(),
		"con la pared en el medio no hay tiro")

	var in_range := ConditionPlayerInRange.new()
	in_range.require_line_of_sight = true
	add_child_autofree(in_range)
	assert_eq(in_range.tick(enemy, Blackboard.new()), BeehaveNode.FAILURE,
		"y la rama de disparo no se abre")


## Sin la pared la rama se abre igual que siempre: la vision es un requisito nuevo,
## no un enemigo que dejo de atacar.
func test_line_of_sight_does_not_close_a_clear_shot() -> void:
	var base: Vector3 = _on_floor_at(0.0, 0.0)
	_player.global_position = base + Vector3(0.0, 0.5, -5.0)
	var enemy: Enemy = await _spawn("ranger", base + Vector3(0.0, 0.0, 5.0))

	var in_range := ConditionPlayerInRange.new()
	in_range.require_line_of_sight = true
	add_child_autofree(in_range)
	assert_eq(in_range.tick(enemy, Blackboard.new()), BeehaveNode.SUCCESS,
		"sin nada en el medio, dispara")


## Y sin vision se mueve a buscar el angulo en vez de quedarse a su distancia
## preferida. Es la diferencia entre un enemigo que espera y uno que se colgo.
func test_a_blind_ranged_enemy_repositions_instead_of_holding() -> void:
	var base: Vector3 = _on_floor_at(0.0, 0.0)
	_make_box(Vector3(10, 6, 1), base + Vector3.UP * 3.0)
	_player.global_position = base + Vector3(0.0, 0.5, -5.0)
	var enemy: Enemy = await _spawn("ranger", base + Vector3(0.0, 0.0, 5.0))

	var kite := ActionKeepDistance.new()
	add_child_autofree(kite)
	kite.before_run(enemy, Blackboard.new())
	var result: int = kite.tick(enemy, Blackboard.new())

	assert_eq(result, BeehaveNode.RUNNING, "sin vision no da la posicion por buena")
	assert_true(enemy.is_moving, "y se pone en marcha a buscar el angulo")
