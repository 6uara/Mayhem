extends GutTest
## Speed-bonus tiering and kill rewards read straight from EconomyConfig.


func _make_config() -> EconomyConfig:
	var config := EconomyConfig.new()
	config.speed_bonus_tiers = PackedFloat32Array([0.5, 0.75, 1.0])
	config.speed_bonus_payouts = PackedInt32Array([150, 100, 50])
	return config


func test_kill_reward_per_archetype() -> void:
	var config := _make_config()
	assert_eq(config.get_kill_reward(EnemyData.Archetype.RUSHER), config.kill_reward_rusher)
	assert_eq(config.get_kill_reward(EnemyData.Archetype.ELITE), config.kill_reward_elite)


func test_speed_bonus_top_tier() -> void:
	var config := _make_config()
	assert_eq(config.get_speed_bonus(20.0, 60.0), 150)


func test_speed_bonus_middle_tier() -> void:
	var config := _make_config()
	assert_eq(config.get_speed_bonus(40.0, 60.0), 100)


func test_speed_bonus_boundary_is_inclusive() -> void:
	var config := _make_config()
	assert_eq(config.get_speed_bonus(30.0, 60.0), 150, "exactly at par*0.5 pays the top tier")
	assert_eq(config.get_speed_bonus(60.0, 60.0), 50, "exactly at par still pays")


func test_no_speed_bonus_over_par() -> void:
	var config := _make_config()
	assert_eq(config.get_speed_bonus(90.0, 60.0), 0)


func test_zero_par_time_pays_nothing() -> void:
	var config := _make_config()
	assert_eq(config.get_speed_bonus(10.0, 0.0), 0)
