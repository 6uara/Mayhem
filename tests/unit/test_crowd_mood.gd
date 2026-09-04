extends GutTest
## Cuando el publico se levanta y cuando hace la ola.
##
## La regla que sostiene todo lo demas es que el publico no aplaude cada muerte:
## se calienta con el ritmo y se enfria solo. Sin eso una racha no se siente como
## una racha, se siente como una barra que sube.


func _director() -> CrowdMoodDirector:
	var director := CrowdMoodDirector.new()
	add_child_autofree(director)
	return director


func _crowd() -> CrowdStands:
	var crowd := CrowdStands.new()
	add_child_autofree(crowd)
	crowd.populate(AABB(Vector3.ZERO, Vector3(40.0, 6.0, 40.0)), 4.0)
	return crowd


func test_the_stands_start_dead() -> void:
	assert_eq(_director().get_excitement(), 0.0)


func test_kills_warm_the_crowd_up() -> void:
	var director: CrowdMoodDirector = _director()
	for _i: int in 3:
		EventBus.enemy_killed.emit(&"grunt", Vector3.ZERO, 10)
	assert_almost_eq(director.get_excitement(), director.kill_heat * 3.0, 0.01)


func test_nothing_happening_cools_them_down() -> void:
	# Un publico que se queda encendido deja de reaccionar a nada.
	var crowd: CrowdStands = _crowd()
	var director: CrowdMoodDirector = _director()
	director.add_excitement(0.5)
	director._process(1.0)
	assert_almost_eq(director.get_excitement(), 0.5 - director.cool_per_second, 0.01)
	assert_not_null(crowd)


func test_excitement_never_goes_past_full() -> void:
	var director: CrowdMoodDirector = _director()
	for _i: int in 40:
		EventBus.enemy_killed.emit(&"grunt", Vector3.ZERO, 10)
	assert_eq(director.get_excitement(), 1.0)


func test_a_hot_crowd_starts_a_wave_by_itself() -> void:
	var crowd: CrowdStands = _crowd()
	var director: CrowdMoodDirector = _director()
	assert_false(director.is_waving())
	director.add_excitement(1.0)
	director._process(0.016)
	assert_true(director.is_waving(), "pasado el umbral la ola sale sola")
	assert_not_null(crowd)


func test_the_wave_goes_around_once_and_stops() -> void:
	var crowd: CrowdStands = _crowd()
	var director: CrowdMoodDirector = _director()
	director.start_wave()
	director._process(director.wave_duration * 0.5)
	assert_true(director.is_waving(), "a mitad de camino sigue dando la vuelta")
	director._process(director.wave_duration)
	assert_false(director.is_waving(), "una vuelta y se termina")
	assert_not_null(crowd)


func test_a_long_streak_does_not_leave_them_waving_forever() -> void:
	# La guarda entre olas existe para que el gesto no pierda su peso.
	var crowd: CrowdStands = _crowd()
	var director: CrowdMoodDirector = _director()
	director.add_excitement(1.0)
	director._process(0.016)
	assert_true(director.is_waving())
	director._process(director.wave_duration * 1.1)
	assert_false(director.is_waving())

	director.add_excitement(1.0)
	director._process(0.016)
	assert_false(director.is_waving(), "todavia no le toca a la siguiente ola")
	assert_not_null(crowd)


func test_finishing_a_wave_gets_the_whole_place_up() -> void:
	var crowd: CrowdStands = _crowd()
	var director: CrowdMoodDirector = _director()
	EventBus.wave_completed.emit(0, 20.0, 0.0)
	assert_eq(director.get_excitement(), 1.0)
	assert_true(director.is_waving())
	assert_not_null(crowd)


func test_they_cheer_for_the_player_dying_too() -> void:
	# El publico no vino a verte ganar.
	var crowd: CrowdStands = _crowd()
	var director: CrowdMoodDirector = _director()
	EventBus.player_died.emit()
	assert_eq(director.get_excitement(), 1.0)
	assert_true(director.is_waving())
	assert_not_null(crowd)


func test_a_gift_is_a_small_nudge_not_a_celebration() -> void:
	# El regalo es del publico, no una hazaña del jugador.
	var director: CrowdMoodDirector = _director()
	EventBus.crowd_drop_thrown.emit(&"stun_grenade", Vector3.ZERO)
	assert_lt(director.get_excitement(), director.wave_threshold)
	assert_gt(director.get_excitement(), 0.0)


func test_it_survives_an_arena_with_no_crowd_in_it() -> void:
	# Un shell sin publico -o una escena de test- no puede tirar abajo al
	# director: el resto del juego sigue andando sin tribuna.
	var director: CrowdMoodDirector = _director()
	EventBus.wave_completed.emit(0, 20.0, 0.0)
	director._process(0.5)
	assert_eq(director.get_excitement(), 1.0)
