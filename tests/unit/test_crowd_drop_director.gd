extends GutTest
## Cuando el publico tira, y que.
##
## Las reglas que sostiene: solo se tira durante una oleada, nunca algo que el
## jugador no pueda guardar, la ventana se acorta con las oleadas, y el gadget
## cae lejos del jugador pero adentro de la arena.

const DROP_SCENE: String = "res://scenes/arena/crowd_drop_pickup.tscn"
const PLAYER_SCENE: String = "res://scenes/player/player.tscn"
const TABLE_PATH: String = "res://data/crowd_drop_table.tres"


func before_each() -> void:
	WaveManager.current_index = 0


func after_each() -> void:
	ObjectPool.release_all()


func _table() -> CrowdDropTable:
	return (load(TABLE_PATH) as CrowdDropTable).duplicate() as CrowdDropTable


func _director() -> CrowdDropDirector:
	var director := CrowdDropDirector.new()
	director.table = _table()
	director.drop_scene = load(DROP_SCENE) as PackedScene
	add_child_autofree(director)
	return director


## El jugador tiene que estar en el arbol y en el grupo: el director lo busca por
## `Players.local()`, igual que el shop cuando vendia estos mismos gadgets.
func _player() -> Player:
	var scene := load(PLAYER_SCENE) as PackedScene
	var player := scene.instantiate() as Player
	add_child_autofree(player)
	return player


func test_it_says_quiet_until_a_wave_starts() -> void:
	var director: CrowdDropDirector = _director()
	assert_false(director.is_running(), "entre oleadas no hay a quien entretener")
	EventBus.wave_started.emit(0, null)
	assert_true(director.is_running())
	EventBus.wave_completed.emit(0, 10.0, 0.0)
	assert_false(director.is_running())


func test_a_dead_player_stops_the_crowd() -> void:
	var director: CrowdDropDirector = _director()
	EventBus.wave_started.emit(0, null)
	EventBus.player_died.emit()
	assert_false(director.is_running(), "no hay a quien tirarle")


func test_the_wave_opens_without_a_gift() -> void:
	# El arranque de cada oleada se juega con lo que se traiga puesto.
	var director: CrowdDropDirector = _director()
	EventBus.wave_started.emit(0, null)
	assert_almost_eq(director.get_seconds_left(), director.table.opening_delay, 0.01)


func test_a_throw_lands_a_pickup_the_player_can_take() -> void:
	var player: Player = _player()
	var director: CrowdDropDirector = _director()
	var pickup: CrowdDropPickup = director.throw_now()
	assert_not_null(pickup, "hay lugar en los tres slots, algo tiene que salir")
	assert_not_null(pickup.data)
	assert_gte(player.utility.find_slot(pickup.data.id), 0,
		"solo se tira lo que el jugador puede guardar")


func test_full_slots_mean_the_crowd_keeps_its_gift() -> void:
	# Tirarle una granada a alguien con tres granadas es tirar basura a la arena,
	# y deja al publico como que no mira lo que pasa abajo.
	var player: Player = _player()
	var director: CrowdDropDirector = _director()
	for data: UtilityData in director.table.utilities:
		for _i: int in data.max_carried:
			player.utility.add_charge(data.id)
	assert_null(director.throw_now(), "no queda nada util para tirar")


func test_it_never_throws_what_the_player_does_not_carry() -> void:
	var player: Player = _player()
	var director: CrowdDropDirector = _director()
	# Una utilidad que no esta en ningun slot del jugador no tiene donde entrar.
	var stray := UtilityData.new()
	stray.id = &"nothing_the_player_has"
	stray.max_carried = 2
	director.table.utilities = [stray]
	director.table.weights = PackedFloat32Array([1.0])
	assert_null(director.throw_now())
	assert_eq(player.utility.get_carried(0), 0)


func test_the_drop_lands_away_from_the_player() -> void:
	var player: Player = _player()
	player.global_position = Vector3.ZERO
	var director: CrowdDropDirector = _director()
	var landings: Array[Vector3] = []
	director.drop_thrown.connect(func(_id: StringName, landing: Vector3) -> void:
		landings.append(landing))

	for _i: int in 20:
		assert_not_null(director.throw_now())
	assert_eq(landings.size(), 20)
	for landing: Vector3 in landings:
		var distance: float = Vector2(landing.x, landing.z).length()
		assert_gte(distance, director.min_player_distance - 0.01,
			"cayo encima del jugador: un gadget gratis no cuesta posicion")
		assert_lte(distance, director.max_player_distance + 0.01,
			"cayo tan lejos que nadie lo va a ir a buscar")


func test_a_spot_too_close_to_the_wall_is_rejected() -> void:
	# La banda de distancia se recorta contra la arena, o el gadget termina
	# pegado a la pared o directamente en el foso. Se prueba la regla sola: con
	# la arena real cargada el borde queda lejisimos del jugador y el recorte
	# nunca se dispara.
	var director: CrowdDropDirector = _director()
	var arena := AABB(Vector3.ZERO, Vector3(40.0, 6.0, 40.0))
	assert_true(director._is_inside(Vector3(20.0, 0.0, 20.0), arena), "el centro entra")
	assert_false(director._is_inside(Vector3(1.0, 0.0, 20.0), arena),
		"a un metro de la pared no")
	assert_false(director._is_inside(Vector3(20.0, 0.0, 60.0), arena),
		"y afuera del todo menos")


func test_the_crowd_gets_quicker_as_the_waves_get_worse() -> void:
	# Las oleadas altas son las que piden mas gadget.
	var table: CrowdDropTable = _table()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var early: float = table.roll_interval(0, rng)
	rng.seed = 7
	var late: float = table.roll_interval(8, rng)
	assert_lt(late, early)


func test_the_window_has_a_floor() -> void:
	# Sin piso, en la oleada 20 el publico tira sin parar y el gadget deja de ser
	# algo que hay que administrar.
	var table: CrowdDropTable = _table()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	assert_gte(table.roll_interval(99, rng), table.min_interval_floor)


func test_weights_decide_what_falls_more_often() -> void:
	var table: CrowdDropTable = _table()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	table.weights = PackedFloat32Array([1.0, 0.0, 0.0])
	for _i: int in 30:
		assert_eq(table.pick(rng).id, table.utilities[0].id,
			"un peso en cero no sale nunca")


func test_an_empty_table_throws_nothing() -> void:
	var table: CrowdDropTable = _table()
	table.utilities = []
	assert_null(table.pick(RandomNumberGenerator.new()))
