extends GutTest
## The spawner that turns EventBus.damage_dealt into a pooled DamageNumber.

var _spawner: DamageNumberSpawner
var _target: Node3D
var _original_setting: bool


func before_each() -> void:
	_original_setting = bool(SettingsManager.get_value("hud/damage_numbers", true))
	SettingsManager.set_value("hud/damage_numbers", true)
	_spawner = DamageNumberSpawner.new()
	_spawner.damage_number_scene = load("res://scenes/vfx/damage_number.tscn")
	add_child_autofree(_spawner)
	_target = add_child_autofree(Node3D.new())
	_target.global_position = Vector3(5, 0, 5)
	ObjectPool.clear()


func after_each() -> void:
	SettingsManager.set_value("hud/damage_numbers", _original_setting)
	ObjectPool.clear()


func test_a_hit_spawns_exactly_one_number() -> void:
	EventBus.damage_dealt.emit(_target, 15.0, false)
	assert_eq(ObjectPool.get_active_count(), 1)


func test_zero_damage_spawns_nothing() -> void:
	EventBus.damage_dealt.emit(_target, 0.0, false)
	assert_eq(ObjectPool.get_active_count(), 0)


func test_turning_damage_numbers_off_spawns_nothing() -> void:
	SettingsManager.set_value("hud/damage_numbers", false)
	EventBus.damage_dealt.emit(_target, 15.0, false)
	assert_eq(ObjectPool.get_active_count(), 0)


func test_the_number_spawns_above_the_targets_position() -> void:
	EventBus.damage_dealt.emit(_target, 15.0, false)
	var number: Node3D = ObjectPool._in_use.keys()[0]
	assert_almost_eq(number.global_position.x, _target.global_position.x, 0.2)
	assert_gt(number.global_position.y, _target.global_position.y,
		"the number must float above the target's own origin")


func test_a_target_with_no_3d_position_is_ignored_without_erroring() -> void:
	var flat_target := Node.new()
	add_child_autofree(flat_target)
	EventBus.damage_dealt.emit(flat_target, 15.0, false)
	assert_eq(ObjectPool.get_active_count(), 0)
