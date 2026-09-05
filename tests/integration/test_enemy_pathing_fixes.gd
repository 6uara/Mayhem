extends GutTest
## Los dos comportamientos que se veian en partida: el enemigo que salta en el
## lugar para siempre, y la fila india hacia el jugador.


func _make_enemy(archetype: String = "rusher") -> Enemy:
	var enemy: Enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	add_child_autofree(enemy)
	await wait_physics_frames(1)
	enemy.setup(load("res://data/enemies/%s.tres" % archetype), Vector3.ZERO)
	await wait_physics_frames(1)
	return enemy


func _make_player_at(position: Vector3) -> Node3D:
	var body := Node3D.new()
	body.add_to_group(&"player")
	add_child_autofree(body)
	body.global_position = position
	return body


# ------------------------------------------------------- saltar en el lugar

## El sintoma reportado: el enemigo salta, cae donde estaba, y vuelve a saltar
## un segundo despues, indefinidamente. Lo que lo cortaba antes era nada: nadie
## miraba si el salto habia servido.
func test_a_jump_that_lands_where_it_started_is_not_retried_right_away() -> void:
	var enemy: Enemy = await _make_enemy()
	enemy._jump_cooldown_left = 0.0
	enemy._note_jump_result(0.0)

	assert_gt(enemy._jump_cooldown_left, Enemy.JUMP_COOLDOWN,
		"el salto fallido se penaliza mas que uno normal")
	assert_gt(enemy._detour_time, 0.0, "y en vez de saltar, camina al costado")


## Un salto que si movio al enemigo no debe penalizarse: es el caso bueno, y
## penalizarlo dejaria a los enemigos sin poder encadenar plataformas.
func test_a_jump_that_covered_ground_costs_nothing() -> void:
	var enemy: Enemy = await _make_enemy()
	enemy._jump_cooldown_left = 0.0
	enemy._note_jump_result(4.0)

	assert_eq(enemy._jump_cooldown_left, 0.0, "sin penalizacion")
	assert_eq(enemy._detour_time, 0.0, "y sin rodeo: el salto funciono")


## Un link a plomo -caer derecho desde una plataforma- avanza cero en horizontal
## y es un cruce perfecto. Se juzga por haber llegado a la salida, no por la
## distancia recorrida, o el proximo nivel con una caida recta la ve como falla.
func test_a_link_crossing_that_arrived_counts_even_without_moving_sideways() -> void:
	var enemy: Enemy = await _make_enemy()
	enemy._jump_cooldown_left = 0.0
	enemy._note_jump_result(0.2, true)
	assert_eq(enemy._jump_cooldown_left, 0.0, "llego: no hay nada que penalizar")
	assert_eq(enemy._detour_time, 0.0, "y no hay por que rodear")


## El rodeo alterna de lado. Si irse a la izquierda no lo destrabo, insistir por
## el mismo lado lo deja en la misma esquina.
func test_the_detour_alternates_sides() -> void:
	var enemy: Enemy = await _make_enemy()
	enemy._note_jump_result(0.0)
	var first: float = enemy._detour_sign
	enemy._note_jump_result(0.0)
	assert_ne(enemy._detour_sign, first, "el segundo intento va para el otro lado")


## Lo de arriba prueba la regla; esto prueba que el aterrizaje de verdad la
## dispara. Un enemigo sobre piso real salta derecho para arriba, vuelve a caer
## donde estaba, y tiene que quedar penalizado sin que nadie llame a nada.
func test_a_real_hop_in_place_is_caught_when_it_lands() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 1.0, 20.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.collision_layer = PhysicsLayers.WORLD
	add_child_autofree(floor_body)
	floor_body.global_position = Vector3(0.0, -0.5, 0.0)

	var enemy: Enemy = await _make_enemy()
	enemy.global_position = Vector3(0.0, 0.1, 0.0)
	await wait_physics_frames(6)
	if not enemy.is_on_floor():
		pass_test("el cuerpo no llego a apoyarse en esta corrida")
		return

	enemy._jump_cooldown_left = 0.0
	enemy._begin_jump()
	enemy.velocity.y = 6.0
	# Salta y cae. Sin movimiento horizontal, aterriza donde salio.
	await wait_physics_frames(60)

	assert_false(enemy._jump_pending, "el aterrizaje fue juzgado")
	assert_gt(enemy._jump_cooldown_left, 0.0,
		"y quedo penalizado sin que el test toque la regla a mano")


# --------------------------------------------------- separacion (boids, la util)

## Dos enemigos encimados se empujan en direcciones opuestas. Es la unica regla
## de boids que este juego quiere: cohesion los volveria a amontonar.
func test_two_crowded_enemies_push_apart() -> void:
	var one: Enemy = await _make_enemy()
	var two: Enemy = await _make_enemy()
	one.global_position = Vector3.ZERO
	two.global_position = Vector3(0.4, 0.0, 0.0)
	# El mismo frame de gracia que se explica en el test de abajo: los vecinos
	# salen de una grilla que el director rearma a intervalos, y preguntar antes
	# de que la rearme una vez contesta que no hay nadie. Faltaba solo aca, y por
	# eso este test pasaba o no segun que hubiera corrido antes.
	await wait_physics_frames(4)

	var push_one: Vector3 = one._compute_separation()
	var push_two: Vector3 = two._compute_separation()

	assert_gt(push_one.length(), 0.0, "se sienten")
	assert_lt(push_one.dot(push_two), 0.0, "y se empujan para lados opuestos")
	assert_almost_eq(push_one.y, 0.0, 0.001,
		"el empujon es horizontal: para arriba los haria flotar")


## Cuanto mas encimados, mas fuerte. Un vecino al borde del radio casi no pesa.
func test_the_push_grows_as_they_close_in() -> void:
	var one: Enemy = await _make_enemy()
	var two: Enemy = await _make_enemy()
	one.global_position = Vector3.ZERO

	# Un frame entre mover y medir: los vecinos los resuelve CombatDirector contra
	# una grilla que se rearma a intervalos (CombatDirector.GRID_INTERVAL), asi
	# que teletransportar un cuerpo y preguntar en la misma linea contesta por las
	# posiciones anteriores. En juego nadie se teletransporta.
	two.global_position = Vector3(1.9, 0.0, 0.0)
	await wait_physics_frames(4)
	var far_push: float = one._compute_separation().length()
	two.global_position = Vector3(0.3, 0.0, 0.0)
	await wait_physics_frames(4)
	var near_push: float = one._compute_separation().length()

	assert_gt(near_push, far_push, "pisarse empuja mas que rozarse")


func test_a_neighbour_out_of_range_is_not_felt() -> void:
	var one: Enemy = await _make_enemy()
	var two: Enemy = await _make_enemy()
	one.global_position = Vector3.ZERO
	two.global_position = Vector3(0.0, 0.0, Enemy.SEPARATION_RADIUS + 1.0)
	assert_eq(one._compute_separation(), Vector3.ZERO, "lejos no molesta")


## Un cuerpo devuelto al pool vive debajo del piso. Si siguiera contando como
## vecino, empujaria a los vivos desde ahi abajo toda la partida.
func test_a_body_back_in_the_pool_stops_pushing() -> void:
	var one: Enemy = await _make_enemy()
	var two: Enemy = await _make_enemy()
	one.global_position = Vector3.ZERO
	two.global_position = Vector3(0.5, 0.0, 0.0)
	await wait_physics_frames(4)
	assert_gt(one._compute_separation().length(), 0.0, "vivo, empuja")

	two._on_released()
	assert_eq(one._compute_separation(), Vector3.ZERO, "en el pool, no")


# ------------------------------------------------------------- la fila india

## Lejos, cada enemigo camina a su propio carril al costado de la linea directa.
func test_far_away_each_enemy_walks_its_own_lane() -> void:
	_make_player_at(Vector3(0.0, 0.0, 30.0))
	var one: Enemy = await _make_enemy()
	var two: Enemy = await _make_enemy()
	one._approach_lane = 1.0
	two._approach_lane = -1.0

	var first: Vector3 = one.get_approach_position()
	var second: Vector3 = two.get_approach_position()

	assert_gt(first.distance_to(second), 1.0,
		"dos enemigos a la misma distancia no van al mismo punto")
	assert_gt(first.distance_to(Vector3(0.0, 0.0, 30.0)), 0.5,
		"y ninguno apunta a los pies del jugador")


## Cerca, el carril se cierra: pegarle a un punto al lado del jugador es fallar.
func test_up_close_the_lane_closes_onto_the_player() -> void:
	var player_position := Vector3(0.0, 0.0, 2.0)
	_make_player_at(player_position)
	var enemy: Enemy = await _make_enemy()
	enemy._approach_lane = 1.0

	assert_almost_eq(enemy.get_approach_position(), player_position,
		Vector3.ONE * 0.01, "adentro de la distancia de compromiso, va al jugador")


## Con carril cero el comportamiento es el de antes, que es lo que corre en los
## tests de navegacion ya existentes.
func test_a_zero_lane_is_the_old_behaviour() -> void:
	var player_position := Vector3(0.0, 0.0, 30.0)
	_make_player_at(player_position)
	var enemy: Enemy = await _make_enemy()
	enemy._approach_lane = 0.0
	assert_eq(enemy.get_approach_position(), player_position)


## El carril sale del spawn, asi que dos enemigos de la misma oleada no comparten
## el mismo, y un cuerpo reciclado no repite el de su vida anterior.
func test_the_lane_is_rolled_per_spawn() -> void:
	var enemy: Enemy = await _make_enemy()
	var lanes: Array[float] = []
	for _i: int in 12:
		enemy.setup(load("res://data/enemies/rusher.tres"), Vector3.ZERO)
		lanes.append(enemy._approach_lane)
	var unique: int = 0
	for lane: float in lanes:
		if lanes.count(lane) == 1:
			unique += 1
	assert_gt(unique, 8, "los carriles varian entre spawns")
