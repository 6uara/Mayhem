extends GutTest
## Purchase validation and wave payouts. CLAUDE.md 9 puts economy second only to
## stat aggregation, because a purchase bug is invisible until balance is wrong.


func _make_upgrade(id: StringName, cost: int, stacks: int = 1) -> UpgradeData:
	var modifier := StatModifier.new()
	modifier.stat_key = &"damage"
	modifier.operation = StatModifier.Operation.ADD
	modifier.value = 1.0

	var upgrade := UpgradeData.new()
	upgrade.id = id
	upgrade.display_name = "Test"
	upgrade.cost = cost
	upgrade.max_stacks = stacks
	upgrade.stat_modifiers = [modifier]
	# Global rather than the WEAPON default: these tests exercise purchase flow
	# and stacking, not weapon scoping - a WEAPON upgrade needs a weapon_id or
	# UpgradeManager rejects it outright (see test_weapon_upgrades_need_a_weapon_id).
	upgrade.category = UpgradeData.Category.SURVIVABILITY
	return upgrade


func before_each() -> void:
	UpgradeManager.reset()
	EconomyManager.reset()


func after_each() -> void:
	UpgradeManager.reset()
	EconomyManager.reset()


func test_purchase_deducts_the_cost_and_grants_the_upgrade() -> void:
	EconomyManager.currency = 500
	var upgrade: UpgradeData = _make_upgrade(&"test_buy", 200)
	assert_eq(EconomyManager.try_purchase_upgrade(upgrade),
		EconomyManager.PurchaseResult.OK)
	assert_eq(EconomyManager.currency, 300)
	assert_true(UpgradeManager.has_upgrade(&"test_buy"))


func test_insufficient_funds_is_refused_and_charges_nothing() -> void:
	EconomyManager.currency = 50
	var upgrade: UpgradeData = _make_upgrade(&"test_poor", 200)
	assert_eq(EconomyManager.try_purchase_upgrade(upgrade),
		EconomyManager.PurchaseResult.INSUFFICIENT_FUNDS)
	assert_eq(EconomyManager.currency, 50, "a refused purchase must not take money")
	assert_false(UpgradeManager.has_upgrade(&"test_poor"))


func test_exact_change_is_enough() -> void:
	EconomyManager.currency = 200
	assert_eq(EconomyManager.try_purchase_upgrade(_make_upgrade(&"test_exact", 200)),
		EconomyManager.PurchaseResult.OK)
	assert_eq(EconomyManager.currency, 0)


func test_max_stacks_is_refused_and_charges_nothing() -> void:
	EconomyManager.currency = 1000
	var upgrade: UpgradeData = _make_upgrade(&"test_stack", 100, 2)
	assert_eq(EconomyManager.try_purchase_upgrade(upgrade), EconomyManager.PurchaseResult.OK)
	assert_eq(EconomyManager.try_purchase_upgrade(upgrade), EconomyManager.PurchaseResult.OK)
	var before: int = EconomyManager.currency
	assert_eq(EconomyManager.try_purchase_upgrade(upgrade),
		EconomyManager.PurchaseResult.MAX_STACKS)
	assert_eq(EconomyManager.currency, before, "a maxed upgrade must not take money")
	assert_eq(UpgradeManager.get_stacks(&"test_stack"), 2)


func test_null_upgrade_is_invalid() -> void:
	assert_eq(EconomyManager.try_purchase_upgrade(null), EconomyManager.PurchaseResult.INVALID)


func test_currency_never_goes_negative() -> void:
	EconomyManager.currency = 10
	EconomyManager.currency -= 100
	assert_eq(EconomyManager.currency, 0)


func test_generic_spend_refuses_a_negative_cost() -> void:
	EconomyManager.currency = 100
	assert_eq(EconomyManager.try_spend(&"exploit", -50),
		EconomyManager.PurchaseResult.INVALID)
	assert_eq(EconomyManager.currency, 100, "a negative price must not print money")


## Income arrives on kill_credited, not enemy_killed. The two were the same
## event while there was one player; in coop the host resolves every death in
## the arena and only some of them are its money - see EventBus.
func test_kills_pay_into_the_wave_total() -> void:
	EconomyManager.begin_wave()
	EventBus.kill_credited.emit(10)
	EventBus.kill_credited.emit(10)
	assert_eq(EconomyManager.get_wave_kill_income(), 20)
	assert_eq(EconomyManager.currency, 20)


func test_an_enemy_dying_elsewhere_is_not_income() -> void:
	EconomyManager.begin_wave()
	EventBus.enemy_killed.emit(&"rusher", Vector3.ZERO, 10)
	assert_eq(EconomyManager.get_wave_kill_income(), 0,
		"a death this player was not credited with pays nothing")
	assert_eq(EconomyManager.currency, 0)


## The breakdown is what the wave-complete screen shows; all three income sources
## have to be reported separately or the economy stops being legible.
func test_wave_breakdown_itemises_every_income_source() -> void:
	var wave := WaveData.new()
	wave.par_time = 60.0
	wave.completion_bonus = 100

	EconomyManager.begin_wave()
	EventBus.kill_credited.emit(30)
	var breakdown: Dictionary = EconomyManager.award_wave_bonuses(wave, 20.0, false)

	assert_eq(int(breakdown["kills"]), 30)
	assert_eq(int(breakdown["completion_bonus"]), 100)
	assert_gt(int(breakdown["speed_bonus"]), 0, "cleared well under par")
	assert_gt(int(breakdown["no_damage_bonus"]), 0, "took no damage")


func test_no_damage_bonus_is_withheld_after_taking_damage() -> void:
	var wave := WaveData.new()
	wave.par_time = 60.0
	wave.completion_bonus = 0
	var breakdown: Dictionary = EconomyManager.award_wave_bonuses(wave, 20.0, true)
	assert_eq(int(breakdown["no_damage_bonus"]), 0)


func test_slow_clear_forfeits_only_the_speed_bonus() -> void:
	var wave := WaveData.new()
	wave.par_time = 60.0
	wave.completion_bonus = 100
	var breakdown: Dictionary = EconomyManager.award_wave_bonuses(wave, 200.0, false)
	assert_eq(int(breakdown["speed_bonus"]), 0)
	assert_eq(int(breakdown["completion_bonus"]), 100, "clearing still pays")


func test_reset_returns_to_the_configured_starting_currency() -> void:
	EconomyManager.currency = 999
	EconomyManager.reset()
	assert_eq(EconomyManager.currency, EconomyManager.config.starting_currency)
