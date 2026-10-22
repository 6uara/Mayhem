extends GutTest
## Ningun enemigo puede quedar donde no se lo pueda matar.
##
## El playtest del 2026-10-21 reporto runs que no se podian terminar: un enemigo
## del otro lado de la pared perimetral, en las gradas, y la oleada esperandolo
## para siempre. Tres redes, una por test de abajo:
##
##   1. Al aparecer: un spawn afuera de la arena se corrige antes de existir.
##   2. Durante la pelea: el que termina afuera vuelve adentro solo.
##   3. Ultimo recurso: una oleada que lleva demasiado sin progreso devuelve a
##      los vivos por una puerta y corrige un conteo de vivos colgado.

const ENEMY_SCENE: String = "res://scenes/enemies/enemy.tscn"
const RUSHER: String = "res://data/enemies/rusher.tres"
const BOX := AABB(Vector3(-10.0, 0.0, -10.0), Vector3(20.0, 6.0, 20.0))


## Devuelve Enemies de verdad, para que WaveManager los pueda seguir.
class RealEnemySpawner:
	extends Node

	var scene: PackedScene
	var rescue_points: Array[Vector3] = []
	var spawned: Array[Enemy] = []
	var spawn_position: Vector3 = Vector3.ZERO

	func spawn(enemy_data: EnemyData, _door_ids: Array[StringName]) -> Node:
		return spawn_at(enemy_data, spawn_position)

	func spawn_at(enemy_data: EnemyData, position: Vector3) -> Node:
		var enemy := ObjectPool.acquire(scene) as Enemy
		enemy.setup(enemy_data, position)
		spawned.append(enemy)
		return enemy

	func get_rescue_points() -> Array[Vector3]:
		return rescue_points


var _spawner: RealEnemySpawner


func before_each() -> void:
	ArenaBounds.clear()
	WaveManager.reset()
	_spawner = RealEnemySpawner.new()
	_spawner.scene = load(ENEMY_SCENE)
	add_child_autofree(_spawner)
	WaveManager.spawner = _spawner


func after_each() -> void:
	ArenaBounds.clear()
	ObjectPool.release_all()
	ObjectPool.clear()
	WaveManager.reset()
	WaveManager.spawner = null
	WaveManager.setup([])


func _horizontal(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)


func _inside_box(point: Vector3) -> bool:
	return point.x > BOX.position.x and point.x < BOX.end.x \
		and point.z > BOX.position.z and point.z < BOX.end.z


func _one_enemy_wave() -> void:
	var group := SpawnGroup.new()
	group.enemy_data = load(RUSHER)
	group.count = 1
	group.spawn_door_ids = [&"door_01"] as Array[StringName]
	var wave := WaveData.new()
	wave.spawn_groups = [group]
	WaveManager.setup([wave] as Array[WaveData])
	WaveManager.start_next_wave()


# ------------------------------------------------------------------ la caja

func test_without_an_arena_everything_counts_as_inside() -> void:
	assert_true(ArenaBounds.contains(Vector3(9999.0, -9999.0, 9999.0)),
		"sin caja no hay con que comparar, y corregir a ciegas es peor")


func test_the_box_knows_inside_from_outside() -> void:
	ArenaBounds.set_box(BOX)
	assert_true(ArenaBounds.contains(Vector3(0.0, 1.0, 0.0)))
	assert_true(ArenaBounds.contains(Vector3(10.3, 1.0, 0.0)), "apoyado en la pared no es afuera")
	assert_false(ArenaBounds.contains(Vector3(14.0, 1.0, 0.0)), "en las gradas")
	assert_false(ArenaBounds.contains(Vector3(0.0, -40.0, 0.0)), "debajo del mapa")
	assert_true(ArenaBounds.contains(Vector3(0.0, 30.0, 0.0)),
		"arriba es del volador; la pared llega hasta el techo")


func test_clamping_lands_inside_at_floor_height() -> void:
	ArenaBounds.set_box(BOX)
	var point: Vector3 = ArenaBounds.clamp_inside(Vector3(30.0, 12.0, -40.0), 3.0)
	assert_eq(point, Vector3(7.0, 0.0, -7.0))


# ------------------------------------------------------------- 1. al aparecer

## El caso del reporte: un add del Summoner invocado contra la pared.
func test_a_spawn_outside_the_arena_is_moved_inside() -> void:
	ArenaBounds.set_box(BOX)
	var enemy: Enemy = _spawner.spawn_at(load(RUSHER), Vector3(14.0, 4.0, 0.0))
	assert_true(_inside_box(enemy.global_position),
		"aparecio en %s" % enemy.global_position)


func test_a_spawn_inside_the_arena_is_left_alone() -> void:
	ArenaBounds.set_box(BOX)
	var enemy: Enemy = _spawner.spawn_at(load(RUSHER), Vector3(2.0, 1.0, 3.0))
	assert_almost_eq(_horizontal(enemy.global_position), Vector2(2.0, 3.0), Vector2.ONE * 0.01)


# ------------------------------------------------------- 2. durante la pelea

func test_an_enemy_that_ends_up_outside_is_returned() -> void:
	ArenaBounds.set_box(BOX)
	var enemy: Enemy = _spawner.spawn_at(load(RUSHER), Vector3.ZERO)
	await wait_physics_frames(1)
	enemy.global_position = Vector3(0.0, 3.0, 25.0)
	for _i: int in 90:
		await wait_physics_frames(1)
		if _inside_box(enemy.global_position):
			break
	assert_true(_inside_box(enemy.global_position),
		"sigue afuera en %s" % enemy.global_position)


func test_one_that_fell_under_the_map_is_returned_too() -> void:
	ArenaBounds.set_box(BOX)
	var enemy: Enemy = _spawner.spawn_at(load(RUSHER), Vector3.ZERO)
	await wait_physics_frames(1)
	enemy.global_position = Vector3(1.0, -60.0, 1.0)
	for _i: int in 90:
		await wait_physics_frames(1)
		if enemy.global_position.y > -10.0:
			break
	assert_gt(enemy.global_position.y, -10.0)


# ---------------------------------------------------------- 3. ultimo recurso

func test_a_stalled_wave_brings_the_live_enemies_back_through_a_door() -> void:
	_spawner.rescue_points = [Vector3(5.0, 0.5, 5.0)] as Array[Vector3]
	_spawner.spawn_position = Vector3(-6.0, 0.5, -6.0)
	_one_enemy_wave()
	await wait_physics_frames(2)
	var enemy: Enemy = _spawner.spawned[0]
	watch_signals(EventBus)
	WaveManager._rescue_stalled_wave()
	assert_almost_eq(_horizontal(enemy.global_position), Vector2(5.0, 5.0), Vector2.ONE * 0.5,
		"volvio por la puerta")
	assert_signal_emitted_with_parameters(EventBus, "wave_stall_rescued", [0, 1])


## Un vivo que el conteo cree que existe y no existe: la oleada no puede esperarlo.
func test_a_stalled_wave_waiting_on_a_phantom_enemy_clears() -> void:
	_one_enemy_wave()
	await wait_physics_frames(2)
	WaveManager._alive_enemies += 1
	var enemy: Enemy = _spawner.spawned[0]
	enemy.health.apply_damage(99999.0)
	await wait_physics_frames(1)
	assert_true(WaveManager.is_wave_active, "precondicion: el fantasma traba la oleada")
	WaveManager._rescue_stalled_wave()
	assert_false(WaveManager.is_wave_active, "la red corrige el conteo y la oleada termina")


func test_the_stall_clock_waits_until_everything_has_spawned() -> void:
	_one_enemy_wave()
	WaveManager._pending_spawns = 3
	watch_signals(EventBus)
	WaveManager._process(WaveManager.STALL_TIME + 1.0)
	assert_signal_not_emitted(EventBus, "wave_stall_rescued",
		"un grupo que todavia no llego no es una oleada trabada")


func test_a_hit_on_an_enemy_resets_the_stall_clock() -> void:
	_one_enemy_wave()
	await wait_physics_frames(2)
	WaveManager._process(WaveManager.STALL_TIME - 1.0)
	EventBus.damage_dealt.emit(null, 5.0, false)
	watch_signals(EventBus)
	WaveManager._process(2.0)
	assert_signal_not_emitted(EventBus, "wave_stall_rescued")
