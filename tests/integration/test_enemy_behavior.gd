extends GutTest
## Does a spawned enemy actually chase the player? Guards the whole chain:
## pooling -> setup -> behavior tree instantiation -> leaf ticks -> movement.

var _player: CharacterBody3D
var _enemy: Enemy


func before_each() -> void:
	_player = CharacterBody3D.new()
	_player.add_to_group(&"player")
	add_child_autofree(_player)
	_player.global_position = Vector3(0, 0, -20)

	var scene: PackedScene = load("res://scenes/enemies/enemy.tscn")
	_enemy = ObjectPool.acquire(scene) as Enemy
	_enemy.setup(load("res://data/enemies/rusher.tres"), Vector3.ZERO)


func after_each() -> void:
	ObjectPool.release_all()
	ObjectPool.clear()


func test_enemy_is_active_after_setup() -> void:
	assert_true(_enemy.is_active, "setup() must arm the enemy")
	assert_not_null(_enemy.data, "data")


func test_enemy_finds_the_player() -> void:
	assert_not_null(_enemy.get_player(), "player group lookup")
	assert_almost_eq(_enemy.get_distance_to_player(), 20.0, 0.5)


func test_behavior_tree_is_instantiated_with_the_enemy_as_actor() -> void:
	var holder: Node = _enemy.tree_holder
	assert_eq(holder.get_child_count(), 1, "one tree under the holder")
	var tree := holder.get_child(0) as BeehaveTree
	assert_not_null(tree, "the tree is a BeehaveTree")
	assert_eq(tree.actor, _enemy, "actor must be the enemy, not the holder")


func test_behavior_tree_ticks() -> void:
	var tree := _enemy.tree_holder.get_child(0) as BeehaveTree
	await wait_physics_frames(5)
	assert_ne(tree.status, -1, "the tree must have ticked at least once")


func test_enemy_moves_toward_the_player() -> void:
	var start: Vector3 = _enemy.global_position
	await wait_physics_frames(20)
	var moved: float = Vector2(_enemy.global_position.x - start.x,
		_enemy.global_position.z - start.z).length()
	assert_gt(moved, 0.5, "the rusher should have closed distance")
	assert_lt(_enemy.global_position.z, start.z, "it should move toward the player")


func test_enemy_paths_through_the_real_arena() -> void:
	# The isolated test above exercises the straight-line fallback. This one puts an
	# enemy on the actual baked navmesh, which is where the freeze was reported.
	var arena: Node3D = add_child_autofree(
		load("res://scenes/arena/greybox_arena.tscn").instantiate())
	await wait_physics_frames(3)

	_player.global_position = Vector3(0, 1, 20)
	var enemy := ObjectPool.acquire(load("res://scenes/enemies/enemy.tscn")) as Enemy
	enemy.setup(load("res://data/enemies/rusher.tres"), Vector3(0, 1, -10))

	var start: Vector3 = enemy.global_position
	await wait_physics_frames(30)

	var moved: float = Vector2(enemy.global_position.x - start.x,
		enemy.global_position.z - start.z).length()
	assert_gt(moved, 1.0, "an enemy on the navmesh must close distance, not stand still")
	assert_true(arena.is_inside_tree())


## The playtest report: enemies grinding into the side of a ramp instead of using
## it. The cause was a navmesh island - with the target unreachable the straight-line
## fallback drove them into geometry - so this checks the enemy actually gains height.
func test_enemy_climbs_a_ramp_to_reach_the_player() -> void:
	var arena: Node3D = add_child_autofree(
		load("res://scenes/arena/greybox_arena.tscn").instantiate())
	await wait_physics_frames(3)

	# Player up on the mid-west platform, enemy on the floor below the ramp.
	_player.global_position = Vector3(-24, 3.6, -8)
	var enemy := ObjectPool.acquire(load("res://scenes/enemies/enemy.tscn")) as Enemy
	enemy.setup(load("res://data/enemies/rusher.tres"), Vector3(-24, 0.5, 12))

	var start_y: float = enemy.global_position.y
	await wait_seconds(4.0)

	assert_gt(enemy.global_position.y, start_y + 1.0,
		"the enemy should be climbing the ramp, not stuck against its side")
	assert_true(arena.is_inside_tree())


## An unreachable target must not make an enemy shove itself into a wall.
##
## The chase leaf re-targets the player every 0.2s, so the only honest way to test
## this is to put the player somewhere genuinely unreachable rather than to set a
## target by hand and have the tree overwrite it.
func test_enemy_settles_instead_of_grinding_at_an_unreachable_player() -> void:
	var arena: Node3D = add_child_autofree(
		load("res://scenes/arena/greybox_arena.tscn").instantiate())
	await wait_physics_frames(3)

	# Outside the arena wall: the enemy can approach, but never arrive.
	_player.global_position = Vector3(0, 0.5, 60)
	var enemy := ObjectPool.acquire(load("res://scenes/enemies/enemy.tscn")) as Enemy
	enemy.setup(load("res://data/enemies/rusher.tres"), Vector3(0, 0.5, 24))

	await wait_seconds(4.0)
	var settled: Vector3 = enemy.global_position
	await wait_seconds(1.0)

	var still_pushing: float = Vector2(enemy.velocity.x, enemy.velocity.z).length()
	var actually_moved: float = settled.distance_to(enemy.global_position)
	# Grinding is the combination: full speed commanded, no ground covered.
	assert_false(still_pushing > 3.0 and actually_moved < 0.5,
		"the enemy is pushing at %.1f m/s but covering %.2fm - that is grinding"
			% [still_pushing, actually_moved])
	assert_true(arena.is_inside_tree())


# ------------------------------------------- cadencia desincronizada y salto

## Da un jugador con vida propia, que es lo que el salto necesita para poder
## cobrarle el golpe.
func _player_with_health(at: Vector3) -> HealthComponent:
	_player.global_position = at
	var health := HealthComponent.new()
	health.max_health = 500.0
	_player.add_child(health)
	health.reset()
	return health


## Piso bajo los pies del enemigo, y espera a que lo pise de verdad.
##
## Nadie salta desde el aire, asi que sin piso start_leap() se niega con razon y
## el test mide el vacio en vez del salto. La espera no es decorativa: el enemigo
## se crea en before_each() y el piso recien aca, asi que pasa unos frames
## cayendo - dar por sentado que ya aterrizo hace el test intermitente.
func _ground_the_enemy() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	body.add_child(shape)
	add_child_autofree(body)
	body.global_position = Vector3(0, -0.5, 0)

	_enemy.global_position = Vector3(0, 0.6, 0)
	for _i: int in 60:
		await wait_physics_frames(1)
		if _enemy.is_on_floor():
			return
	fail_test("el enemigo nunca llego a pisar el piso del test")


## Tres enemigos iguales que aparecen juntos no pueden quedar atacando al
## unisono: el jugador come tres proyectiles a la vez o ninguno, y ninguna de las
## dos cosas se puede jugar.
func test_enemies_of_one_archetype_do_not_share_an_attack_cadence() -> void:
	var data: EnemyData = load("res://data/enemies/ranger.tres")
	var cooldowns: Array[float] = []
	for _i: int in 12:
		_enemy.setup(data, Vector3.ZERO)
		_enemy.start_attack_cooldown()
		cooldowns.push_back(_enemy._attack_cooldown_left)

	var unique: Dictionary = {}
	for value: float in cooldowns:
		unique[snappedf(value, 0.001)] = true
	assert_gt(unique.size(), 8,
		"doce esperas seguidas no pueden salir todas iguales")


## Desincronizar no deberia costar dificultad: el jitter va centrado, asi que el
## arquetipo ataca igual de seguido que antes. Un rango que solo suma (1-3s sobre
## el cooldown) tambien separaria las fases, pero de paso le bajaria el daño por
## segundo a la mitad.
func test_the_cooldown_jitter_does_not_change_how_often_the_archetype_attacks() -> void:
	var data: EnemyData = load("res://data/enemies/ranger.tres")
	_enemy.setup(data, Vector3.ZERO)
	var total: float = 0.0
	var samples: int = 400
	for _i: int in samples:
		_enemy.start_attack_cooldown()
		total += _enemy._attack_cooldown_left

	var average: float = total / float(samples)
	assert_almost_eq(average, data.attack_cooldown, data.attack_cooldown * 0.08,
		"el promedio tiene que seguir siendo el attack_cooldown del arquetipo")


## Y el primer ataque de la ola tambien llega escalonado: sin esto el jitter
## recien los separa despues del primer disparo, que sale clavado a la vez.
func test_a_freshly_spawned_wave_does_not_all_attack_on_the_same_frame() -> void:
	var data: EnemyData = load("res://data/enemies/ranger.tres")
	var first: Array[float] = []
	for _i: int in 12:
		_enemy.setup(data, Vector3.ZERO)
		first.push_back(_enemy._attack_cooldown_left)

	var unique: Dictionary = {}
	for value: float in first:
		unique[snappedf(value, 0.001)] = true
	assert_gt(unique.size(), 8, "el desfase inicial tiene que ser por enemigo")
	for value: float in first:
		assert_lte(value, data.attack_cooldown,
			"el desfase nunca puede pasar de un ciclo entero")


## El Rusher se tira encima del jugador en vez de golpear parado. El arco se fija
## al despegar: eso es lo que lo hace esquivable.
func test_a_rusher_leaps_at_the_player() -> void:
	await _ground_the_enemy()
	_player_with_health(Vector3(0, 0, -5))
	await wait_physics_frames(2)

	assert_true(_enemy.data.can_leap, "el rusher salta")
	assert_true(_enemy.start_leap(), "a 5m tiene que animarse")
	assert_true(_enemy.is_leaping(), "queda en el aire")
	assert_gt(_enemy.velocity.y, 0.0, "el salto sale para arriba")
	assert_lt(_enemy.velocity.z, 0.0, "y hacia el jugador")


## Desde lejos no salta: se acerca primero. La rama del arbol falla y cae a
## perseguir, que es lo correcto.
func test_a_leap_is_refused_from_beyond_its_range() -> void:
	await _ground_the_enemy()
	_player_with_health(Vector3(0, 0, -40))
	await wait_physics_frames(2)
	assert_false(_enemy.start_leap(), "40m esta muy lejos para saltar")
	assert_false(_enemy.is_leaping())


## Si alcanza al jugador, cobra - una sola vez, por mas que lo roce varios frames.
func test_a_leap_that_connects_deals_its_damage_once() -> void:
	await _ground_the_enemy()
	var health: HealthComponent = _player_with_health(Vector3(0, 0, -5))
	await wait_physics_frames(2)
	assert_true(_enemy.start_leap())
	# Que no salte de nuevo mientras se mide este: el arbol tiene su propia rama
	# de ataque y un segundo salto ensuciaria el "una sola vez".
	_enemy._attack_cooldown_left = 99.0

	# El arco entero, de verdad: es lo unico que prueba que el contacto ocurre
	# volando y no que la cuenta da bien si se la llama a mano.
	await wait_seconds(_enemy.data.leap_flight_time + 0.3)

	var expected: float = 500.0 - _enemy.data.damage
	assert_almost_eq(health.current_health, expected, 0.01,
		"el salto pega al llegar, y una sola vez")


## Y si el jugador se corre, el salto no pega nada. Es contacto, no alcance.
func test_a_dodged_leap_deals_no_damage_and_leaves_the_enemy_recovering() -> void:
	await _ground_the_enemy()
	var health: HealthComponent = _player_with_health(Vector3(0, 0, -5))
	await wait_physics_frames(2)
	assert_true(_enemy.start_leap())

	# Se movio mientras el enemigo volaba.
	_player.global_position = Vector3(20, 0, -5)
	_enemy._check_leap_contact()
	assert_almost_eq(health.current_health, 500.0, 0.01,
		"esquivarlo tiene que salir gratis")

	_enemy._end_leap()
	assert_false(_enemy.is_leaping(), "aterrizo")
	assert_true(_enemy.is_recovering(),
		"y queda vulnerable un momento: ese es el premio por esquivar")
