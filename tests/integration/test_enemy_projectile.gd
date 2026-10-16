extends GutTest
## La bala de los enemigos que disparan. La usan el Ranger y el Flyer, y no tenia
## tests propios: test_factions.gd prueba la matriz de bandos, no la bala.

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectiles/enemy_projectile.tscn")

var _target: StaticBody3D
var _health: HealthComponent
var _shooter: Node3D


func before_each() -> void:
	_target = StaticBody3D.new()
	_target.add_to_group(&"player")
	_target.collision_layer = PhysicsLayers.PLAYER
	_target.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	shape.shape = box
	_target.add_child(shape)
	_health = HealthComponent.new()
	_health.max_health = 100.0
	_target.add_child(_health)
	add_child_autofree(_target)
	_target.global_position = Vector3(0.0, 1.0, -10.0)

	_shooter = Node3D.new()
	add_child_autofree(_shooter)
	await wait_physics_frames(2)


func after_each() -> void:
	ObjectPool.release_all()


func _fire(direction: Vector3, damage: float = 10.0, speed: float = 40.0) -> EnemyProjectile:
	var shot := ObjectPool.acquire(PROJECTILE_SCENE) as EnemyProjectile
	shot.launch(Vector3(0.0, 1.0, 0.0), direction, damage, speed, _shooter)
	return shot


func test_a_shot_that_reaches_the_player_hurts_and_goes_back_to_the_pool() -> void:
	var shot: EnemyProjectile = _fire(Vector3.FORWARD)
	await wait_physics_frames(30)
	assert_eq(_health.current_health, 90.0)
	assert_false(ObjectPool._in_use.has(shot), "se devolvio al pool al pegar")


func test_a_cosmetic_shot_hits_but_takes_no_health() -> void:
	var shot := ObjectPool.acquire(PROJECTILE_SCENE) as EnemyProjectile
	shot.launch_cosmetic(Vector3(0.0, 1.0, 0.0), Vector3.FORWARD, 40.0, _shooter)
	await wait_physics_frames(30)
	assert_eq(_health.current_health, 100.0)
	assert_false(ObjectPool._in_use.has(shot), "pero se termina igual")


## Del pool sale una bala que pudo haber sido cosmetica: tiene que volver a
## lastimar cuando la reusa un disparo de verdad.
func test_a_recycled_cosmetic_shot_hurts_again() -> void:
	var shot := ObjectPool.acquire(PROJECTILE_SCENE) as EnemyProjectile
	shot.launch_cosmetic(Vector3(0.0, 1.0, 0.0), Vector3.BACK, 40.0, _shooter)
	ObjectPool.release(shot)
	_fire(Vector3.FORWARD)
	await wait_physics_frames(30)
	assert_eq(_health.current_health, 90.0)


func test_a_shot_that_misses_expires_on_its_own() -> void:
	var shot: EnemyProjectile = _fire(Vector3.BACK, 10.0, 1.0)
	shot._physics_process(EnemyProjectile.MAX_LIFETIME + 0.1)
	assert_false(ObjectPool._in_use.has(shot))
	assert_eq(_health.current_health, 100.0)


func test_a_shot_of_the_players_own_faction_passes_through() -> void:
	_shooter.add_to_group(&"player")
	_fire(Vector3.FORWARD)
	await wait_physics_frames(30)
	assert_eq(_health.current_health, 100.0, "no hay fuego amigo")


## El tirador puede desaparecer con la bala en el aire -un enemigo que se libera,
## una escena que se descarta-. La bala le pedia el mundo de fisica al tirador y
## reventaba con "previously freed" en el frame siguiente.
func test_a_shot_outlives_the_enemy_that_fired_it() -> void:
	var shooter := Node3D.new()
	add_child(shooter)
	var shot := ObjectPool.acquire(PROJECTILE_SCENE) as EnemyProjectile
	shot.launch(Vector3(0.0, 1.0, 0.0), Vector3.FORWARD, 10.0, 40.0, shooter)
	shooter.free()
	await wait_physics_frames(30)
	assert_eq(_health.current_health, 90.0, "la bala sigue siendo de la horda y pega")
	assert_false(ObjectPool._in_use.has(shot))
