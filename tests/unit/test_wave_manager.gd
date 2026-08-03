extends GutTest
## Wave clear detection, including the edge cases called out in CLAUDE.md 9:
## enemies that die to something other than the player, and summoned adds that
## outlive their summoner.
##
## A fake spawner stands in for the arena so these stay pure-logic tests.


class FakeSpawner:
	extends Node
	## Records what it was asked to spawn and hands back stand-in nodes.

	var spawned: Array[EnemyData] = []
	var telegraphed: Array = []
	var closed: Array = []
	var next_returns_null: bool = false

	func telegraph(door_ids: Array[StringName]) -> void:
		telegraphed.push_back(door_ids)

	func close_doors(door_ids: Array[StringName]) -> void:
		closed.push_back(door_ids)

	func spawn(enemy_data: EnemyData, _door_ids: Array[StringName]) -> Node:
		if next_returns_null:
			return null
		spawned.push_back(enemy_data)
		return self

	func spawn_at(enemy_data: EnemyData, _position: Vector3) -> Node:
		spawned.push_back(enemy_data)
		return self


var _spawner: FakeSpawner
var _enemy: EnemyData


func before_each() -> void:
	_enemy = EnemyData.new()
	_enemy.id = &"test_enemy"
	_enemy.reward_currency = 5

	_spawner = FakeSpawner.new()
	add_child_autofree(_spawner)
	WaveManager.reset()
	WaveManager.spawner = _spawner


func after_each() -> void:
	WaveManager.reset()
	WaveManager.spawner = null
	WaveManager.setup([])


func _make_wave(count: int, delay: float = 0.0, interval: float = 0.0) -> WaveData:
	var group := SpawnGroup.new()
	group.enemy_data = _enemy
	group.count = count
	group.delay = delay
	group.interval = interval
	group.spawn_door_ids = [&"door_01"] as Array[StringName]

	var wave := WaveData.new()
	wave.wave_index = 0
	wave.spawn_groups = [group]
	wave.par_time = 60.0
	wave.completion_bonus = 100
	return wave


func _kill_one() -> void:
	EventBus.enemy_killed.emit(_enemy.id, Vector3.ZERO, _enemy.reward_currency)


func test_wave_counts_every_enemy_in_its_groups() -> void:
	var wave: WaveData = _make_wave(4)
	assert_eq(wave.get_total_enemy_count(), 4)


func test_starting_a_wave_reports_the_full_remaining_count() -> void:
	WaveManager.setup([_make_wave(3)])
	WaveManager.start_next_wave()
	assert_eq(WaveManager.get_remaining_count(), 3)
	assert_true(WaveManager.is_wave_active)


func test_wave_is_not_clear_while_enemies_are_alive() -> void:
	WaveManager.setup([_make_wave(2)])
	WaveManager.start_next_wave()
	await wait_physics_frames(3)
	_kill_one()
	assert_true(WaveManager.is_wave_active, "one enemy is still alive")


func test_wave_completes_when_the_last_enemy_dies() -> void:
	watch_signals(EventBus)
	WaveManager.setup([_make_wave(2)])
	WaveManager.start_next_wave()
	await wait_physics_frames(3)
	_kill_one()
	_kill_one()
	assert_false(WaveManager.is_wave_active)
	assert_signal_emitted(EventBus, "wave_completed")


## An enemy killed by a hazard emits the same signal, so the count still drains.
func test_hazard_kills_count_toward_the_clear() -> void:
	WaveManager.setup([_make_wave(1)])
	WaveManager.start_next_wave()
	await wait_physics_frames(3)
	EventBus.enemy_killed.emit(&"something_else", Vector3.ZERO, 0)
	assert_false(WaveManager.is_wave_active, "the source of the kill does not matter")


func test_summoned_adds_keep_the_wave_alive() -> void:
	WaveManager.setup([_make_wave(1)])
	WaveManager.start_next_wave()
	await wait_physics_frames(3)
	WaveManager.spawn_summoned(_enemy, Vector3.ZERO)
	_kill_one()  # the summoner dies
	assert_true(WaveManager.is_wave_active, "the add is still alive")
	_kill_one()  # the add dies
	assert_false(WaveManager.is_wave_active)


func test_summoning_is_ignored_outside_an_active_wave() -> void:
	assert_null(WaveManager.spawn_summoned(_enemy, Vector3.ZERO))


func test_a_wave_of_malformed_groups_still_completes() -> void:
	# Otherwise a bad .tres would hang the run forever.
	var wave := WaveData.new()
	var broken := SpawnGroup.new()
	broken.enemy_data = null
	broken.count = 3
	wave.spawn_groups = [broken]
	wave.par_time = 60.0

	WaveManager.setup([wave])
	WaveManager.start_next_wave()
	await wait_physics_frames(3)
	assert_false(WaveManager.is_wave_active, "a wave that can never spawn must not hang")


func test_doors_are_telegraphed_before_enemies_appear() -> void:
	WaveManager.setup([_make_wave(1)])
	WaveManager.start_next_wave()
	await wait_physics_frames(3)
	assert_eq(_spawner.telegraphed.size(), 1, "the group telegraphed its doors once")
	assert_eq(_spawner.spawned.size(), 1)


func test_last_wave_is_reported() -> void:
	WaveManager.setup([_make_wave(1), _make_wave(1)])
	WaveManager.start_next_wave()
	assert_false(WaveManager.is_last_wave())
	await wait_physics_frames(3)
	_kill_one()
	WaveManager.start_next_wave()
	assert_true(WaveManager.is_last_wave())


func test_no_wave_starts_past_the_end_of_the_list() -> void:
	WaveManager.setup([_make_wave(1)])
	assert_true(WaveManager.start_next_wave())
	await wait_physics_frames(3)
	_kill_one()
	assert_false(WaveManager.start_next_wave(), "the match is over, not looping")


func test_reset_abandons_an_in_flight_wave() -> void:
	WaveManager.setup([_make_wave(3, 0.0, 0.5)])
	WaveManager.start_next_wave()
	WaveManager.reset()
	await wait_physics_frames(3)
	assert_false(WaveManager.is_wave_active)
	assert_eq(WaveManager.get_remaining_count(), 0)


func test_spawn_group_duration_accounts_for_delay_and_interval() -> void:
	var group := SpawnGroup.new()
	group.count = 4
	group.delay = 2.0
	group.interval = 0.5
	assert_almost_eq(group.get_total_duration(), 3.5, 0.001)
