extends GutTest
## Damage falloff curve and headshot multiplier.


func _make_weapon() -> WeaponData:
	var weapon := WeaponData.new()
	weapon.damage = 20.0
	weapon.headshot_multiplier = 2.0
	weapon.falloff_start = 20.0
	weapon.falloff_end = 40.0
	weapon.falloff_min_multiplier = 0.5
	weapon.fire_rate = 10.0
	return weapon


func test_no_falloff_inside_start_range() -> void:
	var weapon := _make_weapon()
	assert_eq(weapon.get_falloff_multiplier(5.0), 1.0)
	assert_eq(weapon.get_falloff_multiplier(20.0), 1.0)


func test_falloff_is_linear_between_start_and_end() -> void:
	var weapon := _make_weapon()
	assert_almost_eq(weapon.get_falloff_multiplier(30.0), 0.75, 0.0001)


func test_falloff_clamps_at_minimum() -> void:
	var weapon := _make_weapon()
	assert_eq(weapon.get_falloff_multiplier(40.0), 0.5)
	assert_eq(weapon.get_falloff_multiplier(200.0), 0.5)


func test_headshot_multiplier_applies_after_falloff() -> void:
	var weapon := _make_weapon()
	assert_almost_eq(weapon.get_damage(30.0, true), 30.0, 0.0001)  # 20 * 0.75 * 2
	assert_almost_eq(weapon.get_damage(30.0, false), 15.0, 0.0001)


func test_shot_interval_from_fire_rate() -> void:
	var weapon := _make_weapon()
	assert_almost_eq(weapon.get_shot_interval(), 0.1, 0.0001)
