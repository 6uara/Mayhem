extends GutTest
## The between-wave loop: clearing a non-final wave must open the shop, and closing
## the shop must start the next wave. This is the seam where Phase 3 and Phase 4 meet.


class StubShop:
	extends CanvasLayer
	signal shop_closed()

	var open_count: int = 0
	var last_breakdown: Dictionary = {}

	func open(breakdown: Dictionary, _wave_index: int, _duration: float) -> void:
		open_count += 1
		last_breakdown = breakdown

	func close() -> void:
		shop_closed.emit()


var _director: MatchDirector
var _shop: StubShop


func _make_wave(count: int) -> WaveData:
	var group := SpawnGroup.new()
	group.enemy_data = EnemyData.new()
	group.count = count
	group.spawn_door_ids = [&"door_01"] as Array[StringName]

	var wave := WaveData.new()
	wave.spawn_groups = [group]
	wave.par_time = 60.0
	wave.completion_bonus = 50
	return wave


func before_each() -> void:
	WaveManager.reset()
	EconomyManager.reset()
	_shop = StubShop.new()
	add_child_autofree(_shop)

	_director = MatchDirector.new()
	_director.waves = [_make_wave(1), _make_wave(1)]
	_director.shop_screen = _shop
	_director.first_wave_delay = 0.0
	_director.shop_open_delay = 0.0
	add_child_autofree(_director)
	await wait_physics_frames(3)


func after_each() -> void:
	WaveManager.reset()
	WaveManager.spawner = null
	WaveManager.setup([])
	EconomyManager.reset()


func test_the_match_starts_running() -> void:
	assert_true(_director.is_running)


func test_clearing_a_wave_opens_the_shop_with_the_breakdown() -> void:
	EventBus.enemy_killed.emit(&"test", Vector3.ZERO, 10)
	await wait_seconds(0.3)
	assert_eq(_shop.open_count, 1, "the shop opened between waves")
	assert_true(_shop.last_breakdown.has("speed_bonus"),
		"the shop receives the itemised payout")


func test_closing_the_shop_starts_the_next_wave() -> void:
	EventBus.enemy_killed.emit(&"test", Vector3.ZERO, 10)
	await wait_seconds(0.3)
	_shop.close()
	await wait_seconds(0.8)
	assert_eq(WaveManager.current_index, 1, "the second wave started")


func test_the_final_wave_ends_the_match_instead_of_shopping() -> void:
	watch_signals(EventBus)
	EventBus.enemy_killed.emit(&"test", Vector3.ZERO, 10)
	await wait_seconds(0.3)
	_shop.close()
	await wait_seconds(0.8)
	EventBus.enemy_killed.emit(&"test", Vector3.ZERO, 10)
	await wait_seconds(0.3)

	assert_eq(_shop.open_count, 1, "no shop after the last wave")
	assert_false(_director.is_running, "the match resolved")
	assert_signal_emitted(EventBus, "match_completed")


func test_player_death_stops_the_match() -> void:
	EventBus.player_died.emit()
	await wait_physics_frames(2)
	assert_false(_director.is_running)
