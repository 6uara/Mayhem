class_name Shop
extends Node
## Builds each visit's offer list and executes purchases.
##
## Validation lives here and in EconomyManager, never in the UI: the UI asks what
## is affordable and calls buy(), so a broken button cannot hand out free upgrades.

signal offers_changed(offers: Array[Dictionary])
signal purchase_succeeded(offer: Dictionary)
signal purchase_failed(offer: Dictionary, reason: EconomyManager.PurchaseResult)

enum Kind { UPGRADE, WEAPON, UTILITY }

@export var catalog: ShopCatalog
@export var purchase_sound: AudioStream
@export var denied_sound: AudioStream

## Offers for the current visit: { kind, id, name, description, cost, category }
var offers: Array[Dictionary] = []

var _player: Player
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


# Public API

## Rebuilds the offer list. Sold-out entries (max stacks, already-owned weapons,
## full utility slots) are filtered before the player ever sees them.
func roll_offers() -> void:
	offers.clear()
	if catalog == null:
		push_warning("Shop: no catalog assigned")
		offers_changed.emit(offers)
		return

	var pool: Array[Dictionary] = _build_pool()
	var picked: Array[Dictionary] = []

	if catalog.guarantee_one_per_category:
		for category: int in [UpgradeData.Category.MOBILITY, UpgradeData.Category.WEAPON,
				UpgradeData.Category.SURVIVABILITY]:
			var candidates: Array[Dictionary] = pool.filter(
				func(entry: Dictionary) -> bool:
					return entry["kind"] == Kind.UPGRADE and entry["category"] == category)
			if candidates.is_empty():
				continue
			var chosen: Dictionary = candidates[_rng.randi_range(0, candidates.size() - 1)]
			picked.push_back(chosen)
			pool.erase(chosen)

	while picked.size() < catalog.offers_per_visit and not pool.is_empty():
		var index: int = _rng.randi_range(0, pool.size() - 1)
		picked.push_back(pool[index])
		pool.remove_at(index)

	offers = picked
	offers_changed.emit(offers)


func can_afford(offer: Dictionary) -> bool:
	return EconomyManager.can_afford(int(offer["cost"]))


## Executes a purchase. Returns OK, or the reason it was refused.
func buy(offer: Dictionary) -> EconomyManager.PurchaseResult:
	var result: EconomyManager.PurchaseResult = _execute(offer)
	if result == EconomyManager.PurchaseResult.OK:
		AudioPool.play_2d(purchase_sound, AudioPool.BUS_UI)
		offers.erase(offer)
		purchase_succeeded.emit(offer)
		offers_changed.emit(offers)
	else:
		AudioPool.play_2d(denied_sound, AudioPool.BUS_UI)
		purchase_failed.emit(offer, result)
	return result


# Private

func _execute(offer: Dictionary) -> EconomyManager.PurchaseResult:
	match int(offer["kind"]):
		Kind.UPGRADE:
			return EconomyManager.try_purchase_upgrade(catalog.find_upgrade(offer["id"]))
		Kind.WEAPON:
			return _buy_weapon(offer)
		Kind.UTILITY:
			return _buy_utility(offer)
	return EconomyManager.PurchaseResult.INVALID


func _buy_weapon(offer: Dictionary) -> EconomyManager.PurchaseResult:
	var holder: WeaponHolder = _get_holder()
	if holder == null:
		return EconomyManager.PurchaseResult.INVALID
	if holder.owns(offer["id"]):
		return EconomyManager.PurchaseResult.MAX_STACKS
	var result: EconomyManager.PurchaseResult = EconomyManager.try_spend(
		offer["id"], int(offer["cost"]))
	if result != EconomyManager.PurchaseResult.OK:
		return result
	holder.acquire(offer["id"])
	return EconomyManager.PurchaseResult.OK


func _buy_utility(offer: Dictionary) -> EconomyManager.PurchaseResult:
	var utility: UtilityComponent = _get_utility()
	if utility == null:
		return EconomyManager.PurchaseResult.INVALID
	var slot: int = utility.find_slot(offer["id"])
	if slot < 0:
		return EconomyManager.PurchaseResult.INVALID
	var data: UtilityData = utility.get_slot_data(slot)
	if utility.get_carried(slot) >= data.max_carried:
		return EconomyManager.PurchaseResult.MAX_STACKS
	var result: EconomyManager.PurchaseResult = EconomyManager.try_spend(
		offer["id"], int(offer["cost"]))
	if result != EconomyManager.PurchaseResult.OK:
		return result
	utility.add_charge(offer["id"])
	return EconomyManager.PurchaseResult.OK


func _build_pool() -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	var holder: WeaponHolder = _get_holder()
	var utility: UtilityComponent = _get_utility()

	for upgrade: UpgradeData in catalog.upgrades:
		if upgrade == null or not UpgradeManager.can_add(upgrade):
			continue  # Maxed out: never offered.
		pool.push_back({
			"kind": Kind.UPGRADE, "id": upgrade.id, "name": upgrade.display_name,
			"description": upgrade.description, "cost": upgrade.cost,
			"category": int(upgrade.category),
			"owned": UpgradeManager.get_stacks(upgrade.id),
			"max_stacks": upgrade.max_stacks,
		})

	for weapon: WeaponData in catalog.weapons:
		if weapon == null or (holder != null and holder.owns(weapon.id)):
			continue
		pool.push_back({
			"kind": Kind.WEAPON, "id": weapon.id, "name": weapon.display_name,
			"description": "New weapon.", "cost": catalog.get_weapon_price(weapon.id),
			"category": -1, "owned": 0, "max_stacks": 1,
		})

	for data: UtilityData in catalog.utilities:
		if data == null or utility == null:
			continue
		var slot: int = utility.find_slot(data.id)
		if slot < 0 or utility.get_carried(slot) >= data.max_carried:
			continue
		pool.push_back({
			"kind": Kind.UTILITY, "id": data.id, "name": data.display_name,
			"description": "Restock. Carry up to %d." % data.max_carried,
			"cost": data.cost, "category": -1,
			"owned": utility.get_carried(slot), "max_stacks": data.max_carried,
		})
	return pool


func _get_player() -> Player:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Player
	return _player


func _get_holder() -> WeaponHolder:
	var player: Player = _get_player()
	return player.weapon_holder if player != null else null


func _get_utility() -> UtilityComponent:
	var player: Player = _get_player()
	return player.utility if player != null else null
