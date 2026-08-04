class_name ShopCatalog
extends Resource
## Everything buyable, and the prices. One resource so the whole shop can be
## rebalanced without touching a scene (CLAUDE.md 1.2).

## A weapon for sale. Weapons are not UpgradeData - buying one grants a gun rather
## than modifying a stat - so they carry their price here.
@export var weapons: Array[WeaponData] = []
@export var weapon_prices: PackedInt32Array = PackedInt32Array()

@export var upgrades: Array[UpgradeData] = []
@export var utilities: Array[UtilityData] = []

@export_group("Offer")
## How many entries the shop offers per visit. Fewer than the catalogue holds, so
## a run does not see everything and purchase order matters.
@export var offers_per_visit: int = 6
## Offers always include at least one of each category when possible, so a run is
## never forced down a single track by bad luck.
@export var guarantee_one_per_category: bool = true


func get_weapon_price(weapon_id: StringName) -> int:
	for i: int in weapons.size():
		if weapons[i] != null and weapons[i].id == weapon_id:
			return weapon_prices[i] if i < weapon_prices.size() else 0
	return 0


func find_weapon(weapon_id: StringName) -> WeaponData:
	for weapon: WeaponData in weapons:
		if weapon != null and weapon.id == weapon_id:
			return weapon
	return null


func find_upgrade(upgrade_id: StringName) -> UpgradeData:
	for upgrade: UpgradeData in upgrades:
		if upgrade != null and upgrade.id == upgrade_id:
			return upgrade
	return null


func find_utility(utility_id: StringName) -> UtilityData:
	for utility: UtilityData in utilities:
		if utility != null and utility.id == utility_id:
			return utility
	return null
