extends GutTest
## The shop, weapon switching and utility charges, driven through the real player
## scene - these only mean anything wired together.

var _player: Player
var _shop: Shop


func before_each() -> void:
	UpgradeManager.reset()
	EconomyManager.reset()
	_player = add_child_autofree(load("res://scenes/player/player.tscn").instantiate())
	_shop = Shop.new()
	_shop.catalog = load("res://data/economy/shop_catalog.tres")
	add_child_autofree(_shop)
	await wait_physics_frames(2)


func after_each() -> void:
	UpgradeManager.reset()
	EconomyManager.reset()


# Weapons

func test_player_starts_with_only_the_pistol() -> void:
	var holder: WeaponHolder = _player.weapon_holder
	assert_eq(holder.get_owned().size(), 1)
	assert_true(holder.owns(&"pistol"), "the pistol is the starting weapon")
	assert_false(holder.owns(&"shotgun"))


func test_all_four_weapons_exist_on_the_player() -> void:
	assert_eq(_player.weapon_holder.get_all().size(), 4)


func test_switching_to_an_unowned_weapon_does_nothing() -> void:
	_player.weapon_holder.select_slot(2)
	await wait_physics_frames(2)
	assert_eq(_player.weapon.data.id, &"pistol")


func test_acquiring_a_weapon_equips_it_after_the_swap() -> void:
	var holder: WeaponHolder = _player.weapon_holder
	assert_true(holder.acquire(&"shotgun"))
	assert_true(holder.owns(&"shotgun"))
	# The swap is not instant; that delay is the cost of switching.
	assert_true(holder.is_swapping, "a swap should be in progress")
	await wait_seconds(holder.swap_time + 0.1)
	assert_eq(_player.weapon.data.id, &"shotgun")


func test_a_weapon_cannot_be_acquired_twice() -> void:
	var holder: WeaponHolder = _player.weapon_holder
	assert_true(holder.acquire(&"smg"))
	assert_false(holder.acquire(&"smg"), "already owned")


func test_each_weapon_keeps_its_own_ammo_across_switches() -> void:
	var holder: WeaponHolder = _player.weapon_holder
	holder.acquire(&"smg")
	await wait_seconds(holder.swap_time + 0.1)

	var smg: WeaponComponent = holder.find_by_id(&"smg")
	var pistol: WeaponComponent = holder.find_by_id(&"pistol")
	smg._ammo = 3
	pistol._ammo = 9

	holder.select_slot(0)
	await wait_seconds(holder.swap_time + 0.1)
	assert_eq(_player.weapon.get_ammo(), 9, "the pistol kept its own count")
	assert_eq(smg.get_ammo(), 3, "the SMG kept its own count while holstered")


# Utilities

func test_utilities_start_empty_and_cannot_be_thrown() -> void:
	var utility: UtilityComponent = _player.utility
	assert_eq(utility.get_carried(0), 0)
	assert_false(utility.can_throw(0), "nothing carried, nothing to throw")


func test_buying_a_utility_adds_a_charge_up_to_its_maximum() -> void:
	var utility: UtilityComponent = _player.utility
	var data: UtilityData = utility.get_slot_data(0)
	for i: int in data.max_carried:
		assert_true(utility.add_charge(data.id), "charge %d" % i)
	assert_false(utility.add_charge(data.id), "cannot carry more than max_carried")
	assert_eq(utility.get_carried(0), data.max_carried)


func test_throwing_spends_a_charge_and_starts_the_cooldown() -> void:
	var utility: UtilityComponent = _player.utility
	var data: UtilityData = utility.get_slot_data(0)
	utility.add_charge(data.id)
	utility.add_charge(data.id)

	assert_true(utility.throw(0))
	assert_eq(utility.get_carried(0), 1, "one charge spent")
	assert_false(utility.can_throw(0), "still on cooldown despite carrying one")
	ObjectPool.release_all()


# Shop

func test_shop_offers_are_rolled_and_bounded() -> void:
	_shop.roll_offers()
	assert_gt(_shop.offers.size(), 0, "the shop offered something")
	assert_true(_shop.offers.size() <= _shop.catalog.offers_per_visit)


func test_shop_never_offers_a_weapon_the_player_owns() -> void:
	_player.weapon_holder.acquire(&"shotgun")
	for i: int in 12:
		_shop.roll_offers()
		for offer: Dictionary in _shop.offers:
			if int(offer["kind"]) == Shop.Kind.WEAPON:
				assert_ne(offer["id"], &"shotgun", "owned weapons must not be offered")


func test_shop_never_offers_a_maxed_upgrade() -> void:
	var upgrade: UpgradeData = _shop.catalog.find_upgrade(&"dash_charge")
	EconomyManager.currency = 100000
	for i: int in upgrade.max_stacks:
		UpgradeManager.add_upgrade(upgrade)

	for i: int in 12:
		_shop.roll_offers()
		for offer: Dictionary in _shop.offers:
			assert_ne(offer["id"], &"dash_charge", "maxed upgrades must not be offered")


func test_buying_an_offer_charges_and_applies_it() -> void:
	EconomyManager.currency = 100000
	_shop.roll_offers()
	var offer: Dictionary = _shop.offers[0]
	var before: int = EconomyManager.currency

	assert_eq(_shop.buy(offer), EconomyManager.PurchaseResult.OK)
	assert_eq(EconomyManager.currency, before - int(offer["cost"]))
	assert_false(_shop.offers.has(offer), "a bought offer leaves the shelf")


func test_an_unaffordable_offer_is_refused() -> void:
	EconomyManager.currency = 0
	_shop.roll_offers()
	var offer: Dictionary = _shop.offers[0]
	assert_eq(_shop.buy(offer), EconomyManager.PurchaseResult.INSUFFICIENT_FUNDS)
	assert_true(_shop.offers.has(offer), "a refused offer stays on the shelf")


func test_upgrades_reach_the_player_through_stats() -> void:
	EconomyManager.currency = 100000
	var upgrade: UpgradeData = _shop.catalog.find_upgrade(&"max_health")
	var before: float = _player.health.max_health
	assert_eq(EconomyManager.try_purchase_upgrade(upgrade), EconomyManager.PurchaseResult.OK)
	await wait_physics_frames(2)
	assert_gt(_player.health.max_health, before,
		"a survivability upgrade must actually reach HealthComponent")
