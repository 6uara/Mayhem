extends GutTest
## The economy projection behind the balance editor's curve.


func _config() -> EconomyConfig:
	var config := EconomyConfig.new()
	config.kill_reward_rusher = 10
	config.no_damage_bonus = 100
	config.speed_bonus_tiers = PackedFloat32Array([0.5, 1.0])
	config.speed_bonus_payouts = PackedInt32Array([150, 50])
	config.starting_currency = 0
	return config


func _wave(index: int, count: int) -> WaveData:
	var enemy := EnemyData.new()
	enemy.archetype = EnemyData.Archetype.RUSHER
	var group := SpawnGroup.new()
	group.enemy_data = enemy
	group.count = count
	var wave := WaveData.new()
	wave.wave_index = index
	wave.spawn_groups = [group]
	wave.par_time = 60.0
	wave.completion_bonus = 100
	return wave


func test_kill_income_follows_the_archetype_reward() -> void:
	var payouts: Array = CurveEvaluator.project([_wave(1, 5)], _config(), 0.0)
	assert_eq((payouts[0] as CurveEvaluator.WavePayout).kill_income, 50)


func test_cumulative_series_adds_up_across_waves() -> void:
	var series: PackedInt32Array = CurveEvaluator.cumulative_series(
		[_wave(1, 5), _wave(2, 5)], _config(), 0.0)
	assert_eq(series.size(), 2)
	assert_eq(series[1], series[0] * 2, "identical waves pay identically")


func test_a_better_projected_player_earns_more() -> void:
	var waves: Array = [_wave(1, 5)]
	var poor: PackedInt32Array = CurveEvaluator.cumulative_series(waves, _config(), 0.0)
	var good: PackedInt32Array = CurveEvaluator.cumulative_series(waves, _config(), 1.0)
	assert_gt(good[0], poor[0], "speed and no-damage bonuses are what skill buys")


func test_currency_multiplier_scales_the_whole_curve() -> void:
	var config: EconomyConfig = _config()
	var base: PackedInt32Array = CurveEvaluator.cumulative_series([_wave(1, 5)], config, 0.5)
	config.currency_multiplier = 2.0
	var doubled: PackedInt32Array = CurveEvaluator.cumulative_series([_wave(1, 5)], config, 0.5)
	assert_eq(doubled[0], base[0] * 2)


func test_price_ladder_comes_back_sorted() -> void:
	var catalog := ShopCatalog.new()
	catalog.weapon_prices = PackedInt32Array([500, 200, 900])
	var ladder: PackedInt32Array = CurveEvaluator.price_ladder(catalog)
	assert_eq(ladder, PackedInt32Array([200, 500, 900]))
