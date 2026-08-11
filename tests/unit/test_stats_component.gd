extends GutTest
## StatsComponent: the read path every purchased upgrade in the game flows
## through (WeaponComponent, MovementComponent, Player all resolve their live
## values via get_stat()/get_stat_from() rather than reading data directly).
## Previously zero test files despite that - see 12 Known Issues and Gaps.md.

var _stats: StatsComponent


func _make_upgrade(id: StringName, stat_key: StringName, value: float,
		category: UpgradeData.Category = UpgradeData.Category.SURVIVABILITY,
		max_stacks: int = 1) -> UpgradeData:
	var modifier := StatModifier.new()
	modifier.stat_key = stat_key
	modifier.operation = StatModifier.Operation.ADD
	modifier.value = value
	var upgrade := UpgradeData.new()
	upgrade.id = id
	upgrade.category = category
	upgrade.max_stacks = max_stacks
	upgrade.stat_modifiers = [modifier]
	return upgrade


func before_each() -> void:
	UpgradeManager.reset()
	_stats = add_child_autofree(StatsComponent.new())


func after_each() -> void:
	UpgradeManager.reset()


# get_stat() - cached, upgrade-aware

func test_get_stat_returns_the_fallback_with_no_base_and_no_upgrades() -> void:
	assert_eq(_stats.get_stat(&"nonexistent_stat", 42.0), 42.0)


func test_get_stat_reads_from_base_values() -> void:
	_stats.base_values[&"move_speed"] = 7.5
	assert_eq(_stats.get_stat(StatsComponent.MOVE_SPEED), 7.5)


func test_get_stat_applies_owned_upgrades_on_top_of_the_base() -> void:
	_stats.base_values[&"move_speed"] = 7.5
	UpgradeManager.add_upgrade(_make_upgrade(&"test_speed", StatsComponent.MOVE_SPEED, 2.0))
	assert_eq(_stats.get_stat(StatsComponent.MOVE_SPEED), 9.5)


func test_get_stat_is_cached_until_the_upgrade_set_changes() -> void:
	_stats.base_values[&"move_speed"] = 7.5
	assert_eq(_stats.get_stat(StatsComponent.MOVE_SPEED), 7.5)

	# Mutating base_values directly (bypassing set_base()) must not retroactively
	# change an already-cached read - the cache is keyed by stat_key precisely so
	# a value read once per frame stays stable within that frame.
	_stats.base_values[&"move_speed"] = 100.0
	assert_eq(_stats.get_stat(StatsComponent.MOVE_SPEED), 7.5,
		"a cached value must not silently change underneath a caller")


func test_upgrades_changed_invalidates_the_cache_automatically() -> void:
	_stats.base_values[&"move_speed"] = 7.5
	assert_eq(_stats.get_stat(StatsComponent.MOVE_SPEED), 7.5)

	UpgradeManager.add_upgrade(_make_upgrade(&"test_speed", StatsComponent.MOVE_SPEED, 2.0))
	assert_eq(_stats.get_stat(StatsComponent.MOVE_SPEED), 9.5,
		"StatsComponent must hear UpgradeManager.upgrades_changed and stop serving stale reads")


# set_base() / invalidate()

func test_set_base_updates_the_value_and_clears_that_keys_cache() -> void:
	_stats.get_stat(StatsComponent.MOVE_SPEED, 5.0)  # prime the cache
	_stats.set_base(StatsComponent.MOVE_SPEED, 12.0)
	assert_eq(_stats.get_stat(StatsComponent.MOVE_SPEED), 12.0)


func test_set_base_emits_stats_changed() -> void:
	watch_signals(_stats)
	_stats.set_base(StatsComponent.MOVE_SPEED, 12.0)
	assert_signal_emitted(_stats, "stats_changed")


func test_invalidate_clears_every_cached_stat() -> void:
	_stats.base_values[&"move_speed"] = 7.5
	_stats.base_values[&"jump_velocity"] = 8.0
	_stats.get_stat(StatsComponent.MOVE_SPEED)
	_stats.get_stat(StatsComponent.JUMP_VELOCITY)

	_stats.base_values[&"move_speed"] = 999.0
	_stats.base_values[&"jump_velocity"] = 999.0
	_stats.invalidate()

	assert_eq(_stats.get_stat(StatsComponent.MOVE_SPEED), 999.0)
	assert_eq(_stats.get_stat(StatsComponent.JUMP_VELOCITY), 999.0)


func test_invalidate_emits_stats_changed() -> void:
	watch_signals(_stats)
	_stats.invalidate()
	assert_signal_emitted(_stats, "stats_changed")


# get_stat_from() - weapon-scoped, never cached

func test_get_stat_from_applies_a_weapon_scoped_upgrade_for_the_matching_weapon() -> void:
	UpgradeManager.add_upgrade(
		_make_upgrade(&"test_mag", StatsComponent.MAGAZINE_SIZE, 5.0,
			UpgradeData.Category.WEAPON),
		&"pistol")
	assert_eq(_stats.get_stat_from(StatsComponent.MAGAZINE_SIZE, 14.0, &"pistol"), 19.0)


func test_get_stat_from_does_not_leak_a_weapon_scoped_upgrade_to_another_weapon() -> void:
	UpgradeManager.add_upgrade(
		_make_upgrade(&"test_mag", StatsComponent.MAGAZINE_SIZE, 5.0,
			UpgradeData.Category.WEAPON),
		&"pistol")
	assert_eq(_stats.get_stat_from(StatsComponent.MAGAZINE_SIZE, 30.0, &"shotgun"), 30.0,
		"a different weapon must read its own unmodified base")


func test_get_stat_from_is_never_cached() -> void:
	# Same stat_key, two different weapon_ids, back to back - if this were
	# cached like get_stat() by stat_key alone, the second call would
	# incorrectly return the first weapon's answer.
	UpgradeManager.add_upgrade(
		_make_upgrade(&"test_mag", StatsComponent.MAGAZINE_SIZE, 5.0,
			UpgradeData.Category.WEAPON),
		&"pistol")
	assert_eq(_stats.get_stat_from(StatsComponent.MAGAZINE_SIZE, 14.0, &"pistol"), 19.0)
	assert_eq(_stats.get_stat_from(StatsComponent.MAGAZINE_SIZE, 30.0, &"shotgun"), 30.0)
	assert_eq(_stats.get_stat_from(StatsComponent.MAGAZINE_SIZE, 14.0, &"pistol"), 19.0)


func test_get_stat_from_with_no_weapon_id_only_applies_global_upgrades() -> void:
	UpgradeManager.add_upgrade(_make_upgrade(&"test_health", StatsComponent.MAX_HEALTH, 20.0,
		UpgradeData.Category.SURVIVABILITY))
	assert_eq(_stats.get_stat_from(StatsComponent.MAX_HEALTH, 100.0), 120.0)
