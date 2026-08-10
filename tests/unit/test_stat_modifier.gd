extends GutTest
## Highest-priority tests: StatModifier aggregation silently breaks balance if wrong.
## Order under test: base -> all ADD -> all MULTIPLY -> OVERRIDE.


func _make(stat_key: StringName, operation: StatModifier.Operation, value: float) -> StatModifier:
	var modifier := StatModifier.new()
	modifier.stat_key = stat_key
	modifier.operation = operation
	modifier.value = value
	return modifier


func test_no_modifiers_returns_base() -> void:
	var modifiers: Array[StatModifier] = []
	assert_eq(UpgradeManager.aggregate(10.0, modifiers), 10.0)


func test_add_is_summed() -> void:
	var modifiers: Array[StatModifier] = [
		_make(&"damage", StatModifier.Operation.ADD, 5.0),
		_make(&"damage", StatModifier.Operation.ADD, 2.5),
	]
	assert_eq(UpgradeManager.aggregate(10.0, modifiers), 17.5)


func test_multiply_is_multiplicative() -> void:
	var modifiers: Array[StatModifier] = [
		_make(&"damage", StatModifier.Operation.MULTIPLY, 2.0),
		_make(&"damage", StatModifier.Operation.MULTIPLY, 1.5),
	]
	assert_eq(UpgradeManager.aggregate(10.0, modifiers), 30.0)


func test_add_applies_before_multiply_regardless_of_list_order() -> void:
	var multiply_first: Array[StatModifier] = [
		_make(&"damage", StatModifier.Operation.MULTIPLY, 2.0),
		_make(&"damage", StatModifier.Operation.ADD, 10.0),
	]
	var add_first: Array[StatModifier] = [
		_make(&"damage", StatModifier.Operation.ADD, 10.0),
		_make(&"damage", StatModifier.Operation.MULTIPLY, 2.0),
	]
	# (10 + 10) * 2 == 40, never 10 * 2 + 10 == 30.
	assert_eq(UpgradeManager.aggregate(10.0, multiply_first), 40.0)
	assert_eq(UpgradeManager.aggregate(10.0, add_first), 40.0)


func test_override_wins_over_everything() -> void:
	var modifiers: Array[StatModifier] = [
		_make(&"damage", StatModifier.Operation.ADD, 100.0),
		_make(&"damage", StatModifier.Operation.MULTIPLY, 3.0),
		_make(&"damage", StatModifier.Operation.OVERRIDE, 7.0),
	]
	assert_eq(UpgradeManager.aggregate(10.0, modifiers), 7.0)


func test_last_override_wins() -> void:
	var modifiers: Array[StatModifier] = [
		_make(&"damage", StatModifier.Operation.OVERRIDE, 7.0),
		_make(&"damage", StatModifier.Operation.OVERRIDE, 9.0),
	]
	assert_eq(UpgradeManager.aggregate(10.0, modifiers), 9.0)


func test_null_modifiers_are_ignored() -> void:
	var modifiers: Array[StatModifier] = [
		null,
		_make(&"damage", StatModifier.Operation.ADD, 5.0),
	]
	assert_eq(UpgradeManager.aggregate(10.0, modifiers), 15.0)


func test_stacking_respects_max_stacks() -> void:
	var upgrade := UpgradeData.new()
	upgrade.id = &"test_damage_up"
	upgrade.max_stacks = 2
	upgrade.stat_modifiers = [_make(&"damage", StatModifier.Operation.ADD, 5.0)]
	# Global: this test is about stacking, not weapon scoping (see
	# test_weapon_upgrades_need_a_weapon_id in test_shop_and_loadout.gd).
	upgrade.category = UpgradeData.Category.SURVIVABILITY

	UpgradeManager.reset()
	assert_true(UpgradeManager.add_upgrade(upgrade), "first stack accepted")
	assert_true(UpgradeManager.add_upgrade(upgrade), "second stack accepted")
	assert_false(UpgradeManager.add_upgrade(upgrade), "third stack rejected")
	assert_eq(UpgradeManager.get_stacks(&"test_damage_up"), 2)
	assert_eq(UpgradeManager.get_stat(&"damage", 10.0), 20.0)
	UpgradeManager.reset()


func test_reset_clears_owned_upgrades() -> void:
	var upgrade := UpgradeData.new()
	upgrade.id = &"test_reset"
	upgrade.max_stacks = 1
	upgrade.stat_modifiers = [_make(&"speed", StatModifier.Operation.ADD, 5.0)]
	upgrade.category = UpgradeData.Category.MOBILITY

	UpgradeManager.reset()
	UpgradeManager.add_upgrade(upgrade)
	UpgradeManager.reset()
	assert_false(UpgradeManager.has_upgrade(&"test_reset"))
	assert_eq(UpgradeManager.get_stat(&"speed", 10.0), 10.0)
