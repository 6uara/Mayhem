extends GutTest
## The shop, weapon replacement and utility charges, driven through the real
## player scene - these only mean anything wired together.
##
## Loadout design: the player carries one weapon at a time. Buying a new one
## replaces the current one; a replaced weapon's WEAPON-category upgrades stay
## behind with it (UpgradeManager scopes them by weapon id) rather than
## following the player to the new gun.

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

func test_player_starts_with_the_pistol_equipped() -> void:
	var holder: WeaponHolder = _player.weapon_holder
	assert_true(holder.owns(&"pistol"), "the pistol is the starting weapon")
	assert_false(holder.owns(&"shotgun"))


func test_all_four_weapons_exist_on_the_player() -> void:
	assert_eq(_player.weapon_holder.get_all().size(), 4)


func test_acquiring_a_weapon_equips_it_after_the_swap() -> void:
	var holder: WeaponHolder = _player.weapon_holder
	assert_true(holder.acquire(&"shotgun"))
	assert_true(holder.owns(&"pistol"), "still equipped until the swap finishes")
	# The swap is not instant; that delay is the cost of switching.
	assert_true(holder.is_swapping, "a swap should be in progress")
	await wait_seconds(holder.swap_time + 0.1)
	assert_eq(_player.weapon.data.id, &"shotgun")
	assert_true(holder.owns(&"shotgun"))


func test_buying_a_weapon_replaces_the_current_one() -> void:
	var holder: WeaponHolder = _player.weapon_holder
	holder.acquire(&"shotgun")
	await wait_seconds(holder.swap_time + 0.1)
	assert_true(holder.owns(&"shotgun"))
	assert_false(holder.owns(&"pistol"), "the pistol was replaced, not kept alongside")


func test_acquiring_the_currently_equipped_weapon_does_nothing() -> void:
	var holder: WeaponHolder = _player.weapon_holder
	assert_false(holder.acquire(&"pistol"), "already equipped")


func test_a_replaced_weapon_can_be_bought_back() -> void:
	var holder: WeaponHolder = _player.weapon_holder
	holder.acquire(&"shotgun")
	await wait_seconds(holder.swap_time + 0.1)
	assert_true(holder.acquire(&"pistol"), "a previously-equipped weapon can be re-bought")
	await wait_seconds(holder.swap_time + 0.1)
	assert_true(holder.owns(&"pistol"))


func test_each_weapon_keeps_its_own_ammo_across_a_replacement() -> void:
	var holder: WeaponHolder = _player.weapon_holder
	var pistol: WeaponComponent = holder.find_by_id(&"pistol")
	pistol._ammo = 9

	holder.acquire(&"shotgun")
	await wait_seconds(holder.swap_time + 0.1)
	var shotgun: WeaponComponent = holder.find_by_id(&"shotgun")
	shotgun._ammo = 3

	holder.acquire(&"pistol")
	await wait_seconds(holder.swap_time + 0.1)
	assert_eq(_player.weapon.get_ammo(), 9, "the pistol kept its own count while holstered")
	assert_eq(shotgun.get_ammo(), 3, "the shotgun kept its own count too")


# Weapon-scoped upgrades

func test_weapon_upgrades_need_a_weapon_id() -> void:
	var upgrade: UpgradeData = _shop.catalog.find_upgrade(&"magazine")
	assert_eq(upgrade.category, UpgradeData.Category.WEAPON)
	assert_false(UpgradeManager.add_upgrade(upgrade),
		"a WEAPON upgrade with no weapon_id must be rejected, not silently global")
	assert_push_error("needs a weapon_id")


func test_weapon_upgrades_stay_with_the_weapon_they_were_bought_for() -> void:
	EconomyManager.currency = 100000
	var upgrade: UpgradeData = _shop.catalog.find_upgrade(&"magazine")
	var holder: WeaponHolder = _player.weapon_holder

	assert_eq(EconomyManager.try_purchase_upgrade(upgrade, &"pistol"),
		EconomyManager.PurchaseResult.OK)
	assert_true(UpgradeManager.has_upgrade(&"magazine", &"pistol"))
	assert_false(UpgradeManager.has_upgrade(&"magazine", &"shotgun"),
		"a different weapon must not see the pistol's upgrade")

	holder.acquire(&"shotgun")
	await wait_seconds(holder.swap_time + 0.1)
	assert_true(UpgradeManager.has_upgrade(&"magazine", &"pistol"),
		"the pistol's upgrade is still there, just not equipped")


func test_replacing_a_weapon_does_not_carry_its_upgrades_forward() -> void:
	EconomyManager.currency = 100000
	var magazine: UpgradeData = _shop.catalog.find_upgrade(&"magazine")
	var holder: WeaponHolder = _player.weapon_holder
	var pistol: WeaponComponent = holder.find_by_id(&"pistol")
	var base_magazine: int = pistol.data.magazine_size

	EconomyManager.try_purchase_upgrade(magazine, &"pistol")
	await wait_physics_frames(2)
	assert_gt(pistol.get_magazine_size(), base_magazine, "the upgrade reached the pistol")

	holder.acquire(&"shotgun")
	await wait_seconds(holder.swap_time + 0.1)
	var shotgun: WeaponComponent = holder.find_by_id(&"shotgun")
	assert_eq(shotgun.get_magazine_size(), shotgun.data.magazine_size,
		"the shotgun starts clean - the pistol's magazine upgrade did not follow it")


func test_mobility_and_survivability_upgrades_stay_global() -> void:
	EconomyManager.currency = 100000
	var dash: UpgradeData = _shop.catalog.find_upgrade(&"dash_charge")
	assert_eq(dash.category, UpgradeData.Category.MOBILITY)

	assert_eq(EconomyManager.try_purchase_upgrade(dash), EconomyManager.PurchaseResult.OK)
	assert_true(UpgradeManager.has_upgrade(&"dash_charge"))

	var holder: WeaponHolder = _player.weapon_holder
	holder.acquire(&"shotgun")
	await wait_seconds(holder.swap_time + 0.1)
	assert_true(UpgradeManager.has_upgrade(&"dash_charge"),
		"a global upgrade must survive a weapon swap untouched")


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


## A null entry in the catalogue must be skipped, not dereferenced. Rolling reads
## each upgrade's `category` to scope it per weapon, and doing that before the null
## check crashed every shop open and reroll rather than passing over the hole.
func test_a_null_catalogue_entry_is_skipped_rather_than_crashing() -> void:
	# duplicate() on a Resource is shallow, so the array is duplicated separately -
	# otherwise the null would be pushed into the shared, cached catalogue resource
	# and leak into every other test in the suite.
	var catalog: ShopCatalog = _shop.catalog.duplicate()
	catalog.upgrades = catalog.upgrades.duplicate()
	catalog.upgrades.insert(0, null)
	_shop.catalog = catalog

	# Reaching the assert at all is the point: the bug was a hard crash in here.
	_shop.roll_offers()
	assert_gt(_shop.offers.size(), 0, "the rest of the catalogue still rolls")


func test_shop_never_offers_the_weapon_currently_equipped() -> void:
	# Weapon offers fill the random remainder of the visit, not a guaranteed
	# slot - with offers_per_visit down to 4, 12 unseeded rolls could
	# occasionally never surface one at all, leaving the assert below
	# unexercised (a GUT "Risky: did not assert", not a real pass). A fixed
	# seed plus more rolls makes this deterministic instead.
	_shop._rng.seed = 1
	var saw_a_weapon_offer: bool = false
	for i: int in 40:
		_shop.roll_offers()
		for offer: Dictionary in _shop.offers:
			if int(offer["kind"]) == Shop.Kind.WEAPON:
				saw_a_weapon_offer = true
				assert_ne(offer["id"], &"pistol", "the equipped weapon must not be offered")
	assert_true(saw_a_weapon_offer, "precondition: at least one weapon offer must appear")


func test_shop_offers_a_previously_equipped_weapon_again() -> void:
	var holder: WeaponHolder = _player.weapon_holder
	holder.acquire(&"shotgun")
	await wait_seconds(holder.swap_time + 0.1)

	# Weapon offers fill the random remainder of the visit, not a guaranteed
	# slot (only the three upgrade categories are guaranteed) - a fixed seed
	# makes this deterministic instead of an occasional-miss flake.
	_shop._rng.seed = 1
	var saw_pistol: bool = false
	for i: int in 40:
		_shop.roll_offers()
		for offer: Dictionary in _shop.offers:
			if int(offer["kind"]) == Shop.Kind.WEAPON and offer["id"] == &"pistol":
				saw_pistol = true
	assert_true(saw_pistol, "a replaced weapon is buyable again")


func test_weapon_offers_warn_that_they_replace_the_current_weapon() -> void:
	# Same reasoning as test_shop_offers_a_previously_equipped_weapon_again: a
	# weapon offer fills the random remainder of a visit, not a guaranteed
	# slot, so unseeded rolls could occasionally never surface one.
	_shop._rng.seed = 1
	var saw_a_weapon_offer: bool = false
	for i: int in 40:
		_shop.roll_offers()
		for offer: Dictionary in _shop.offers:
			if int(offer["kind"]) == Shop.Kind.WEAPON:
				saw_a_weapon_offer = true
				assert_true(String(offer["description"]).contains("Replaces"),
					"a weapon offer must say it replaces the current weapon")
	assert_true(saw_a_weapon_offer, "precondition: at least one weapon offer must appear")


func test_shop_never_offers_a_maxed_upgrade() -> void:
	var upgrade: UpgradeData = _shop.catalog.find_upgrade(&"dash_charge")
	EconomyManager.currency = 100000
	for i: int in upgrade.max_stacks:
		UpgradeManager.add_upgrade(upgrade)

	for i: int in 12:
		_shop.roll_offers()
		for offer: Dictionary in _shop.offers:
			assert_ne(offer["id"], &"dash_charge", "maxed upgrades must not be offered")


func test_shop_never_offers_a_weapon_upgrade_maxed_for_the_equipped_weapon() -> void:
	var upgrade: UpgradeData = _shop.catalog.find_upgrade(&"magazine")
	EconomyManager.currency = 100000
	for i: int in upgrade.max_stacks:
		EconomyManager.try_purchase_upgrade(upgrade, &"pistol")

	for i: int in 12:
		_shop.roll_offers()
		for offer: Dictionary in _shop.offers:
			assert_ne(offer["id"], &"magazine", "maxed out for the equipped weapon")


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


func test_buying_a_weapon_upgrade_through_the_shop_scopes_it_to_the_equipped_weapon() -> void:
	EconomyManager.currency = 100000
	_shop.roll_offers()
	var offer: Dictionary
	for candidate: Dictionary in _shop.offers:
		if int(candidate["kind"]) == Shop.Kind.UPGRADE \
				and int(candidate["category"]) == UpgradeData.Category.WEAPON:
			offer = candidate
			break
	if offer.is_empty():
		pending("no WEAPON-category upgrade was rolled this visit")
		return
	assert_eq(_shop.buy(offer), EconomyManager.PurchaseResult.OK)
	assert_true(UpgradeManager.has_upgrade(StringName(offer["id"]), &"pistol"),
		"the shop must scope a WEAPON upgrade purchase to the equipped weapon")


# Reroll

func test_rerolling_costs_more_each_time_within_a_visit() -> void:
	EconomyManager.currency = 100000
	_shop.roll_offers()
	var first_cost: int = _shop.get_reroll_cost()
	assert_eq(_shop.reroll(), EconomyManager.PurchaseResult.OK)
	assert_gt(_shop.get_reroll_cost(), first_cost, "the next reroll costs more")


func test_the_reroll_cost_resets_when_the_shop_reopens() -> void:
	EconomyManager.currency = 100000
	_shop.roll_offers()
	_shop.reroll()
	_shop.reroll()
	var raised_cost: int = _shop.get_reroll_cost()

	_shop.roll_offers()
	assert_lt(_shop.get_reroll_cost(), raised_cost,
		"a fresh visit must not inherit the previous visit's reroll price")
	assert_eq(_shop.get_reroll_cost(), _shop.catalog.reroll_base_cost)


func test_a_reroll_the_player_cannot_afford_changes_nothing() -> void:
	EconomyManager.currency = 100000
	_shop.roll_offers()
	var before: Array[Dictionary] = _shop.offers.duplicate(true)
	EconomyManager.currency = 0

	assert_eq(_shop.reroll(), EconomyManager.PurchaseResult.INSUFFICIENT_FUNDS)
	assert_eq(_shop.offers, before, "a refused reroll must not touch the offer list")
	assert_eq(EconomyManager.currency, 0, "a refused reroll must not take money")


func test_a_reroll_still_offers_one_of_each_category() -> void:
	EconomyManager.currency = 100000
	assert_true(_shop.catalog.guarantee_one_per_category)
	_shop.roll_offers()
	assert_eq(_shop.reroll(), EconomyManager.PurchaseResult.OK)

	for category: int in [
			UpgradeData.Category.MOBILITY, UpgradeData.Category.WEAPON,
			UpgradeData.Category.SURVIVABILITY]:
		var has_category: bool = _shop.offers.any(
			func(offer: Dictionary) -> bool:
				return int(offer["kind"]) == Shop.Kind.UPGRADE and int(offer["category"]) == category)
		assert_true(has_category, "a reroll dropped the guarantee for category %d" % category)
