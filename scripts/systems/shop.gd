class_name Shop
extends Node
## Builds each visit's offer list and executes purchases.
##
## Validation lives here and in EconomyManager, never in the UI: the UI asks what
## is affordable and calls buy(), so a broken button cannot hand out free upgrades.

signal offers_changed(offers: Array[Dictionary])
signal purchase_succeeded(offer: Dictionary)
signal purchase_failed(offer: Dictionary, reason: EconomyManager.PurchaseResult)
signal reroll_cost_changed(cost: int)

## Hubo un tercer valor, UTILITY. Los gadgets salieron del shop cuando pasaron a
## caer de las gradas: conseguirlos tiene que costar posicion y no plata, y
## mientras se pudieran comprar el drop del publico era una alternativa peor a
## apretar un boton en un menu. Ver CrowdDropDirector.
enum Kind { UPGRADE, WEAPON }

@export var catalog: ShopCatalog
@export var purchase_sound: AudioStream
@export var denied_sound: AudioStream

## Offers for the current visit: { kind, id, name, description, cost, category }
var offers: Array[Dictionary] = []

var _player: Player
## La corriente de la semilla de la run (RunSeed): misma semilla, mismas ofertas.
var _rng: RandomNumberGenerator:
	get:
		return RunSeed.rng(&"shop")
## Resets to 0 every time `roll_offers()` opens a fresh visit - a reroll only
## gets pricier within the SAME visit, per `catalog.reroll_cost_increment`.
var _rerolls_this_visit: int = 0


# Public API

## Rebuilds the offer list for a fresh shop visit and resets the reroll price.
## Sold-out entries (max stacks, already-owned weapons) are filtered before the
## player ever sees them.
func roll_offers() -> void:
	_rerolls_this_visit = 0
	reroll_cost_changed.emit(get_reroll_cost())
	_roll()


func can_afford(offer: Dictionary) -> bool:
	return EconomyManager.can_afford(int(offer["cost"]))


## 0 when `catalog.reroll_base_cost <= 0` - a zero-or-negative base cost is how
## a catalog turns the reroll off entirely, per ShopCatalog's docstring.
func get_reroll_cost() -> int:
	if catalog == null or catalog.reroll_base_cost <= 0:
		return 0
	return catalog.reroll_base_cost + catalog.reroll_cost_increment * _rerolls_this_visit


func can_reroll() -> bool:
	return catalog != null and catalog.reroll_base_cost > 0 \
		and EconomyManager.can_afford(get_reroll_cost())


## Spends currency to rebuild the offer list within the SAME visit, at an
## increasing cost (`catalog.reroll_cost_increment` per use, reset by the next
## `roll_offers()`). Still respects `guarantee_one_per_category` - the
## guarantee exists so bad luck can never lock a run out of a whole track, and
## a reroll that bypassed it would reintroduce exactly that, at a price.
func reroll() -> EconomyManager.PurchaseResult:
	if catalog == null or catalog.reroll_base_cost <= 0:
		return EconomyManager.PurchaseResult.INVALID
	var result: EconomyManager.PurchaseResult = EconomyManager.try_spend(
		&"shop_reroll", get_reroll_cost())
	if result != EconomyManager.PurchaseResult.OK:
		AudioPool.play_2d(denied_sound, AudioPool.BUS_UI)
		return result
	_rerolls_this_visit += 1
	reroll_cost_changed.emit(get_reroll_cost())
	AudioPool.play_2d(purchase_sound, AudioPool.BUS_UI)
	_roll()
	return EconomyManager.PurchaseResult.OK


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

## Shared by roll_offers() and reroll() - the only difference between them is
## whether _rerolls_this_visit gets reset first.
func _roll() -> void:
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

	var guaranteed: int = picked.size()
	while picked.size() < catalog.offers_per_visit and not pool.is_empty():
		var index: int = _rng.randi_range(0, pool.size() - 1)
		picked.push_back(pool[index])
		pool.remove_at(index)

	# Una rara como mucho, y no todas las visitas: si todas trajeran una dejarian
	# de ser raras. Ocupa el lugar de una oferta comun sorteada, nunca el de una
	# de las garantizadas por categoria.
	var rare: Dictionary = _roll_rare()
	if not rare.is_empty():
		if picked.size() > guaranteed and picked.size() >= catalog.offers_per_visit:
			picked[picked.size() - 1] = rare
		else:
			picked.push_back(rare)

	offers = picked
	offers_changed.emit(offers)
	# Para el log del playtest: una rara que se ofrece siempre y nunca se compra
	# es una rara cara o aburrida, y eso solo se ve si se anota la oferta.
	var rolled: Array = []
	for offer: Dictionary in offers:
		rolled.append({"id": offer["id"], "rare": bool(offer.get("rare", false))})
	EventBus.shop_offers_rolled.emit(rolled)


## Una oferta rara para esta visita, o vacio. Publica la probabilidad por el
## catalogo y la oleada por WaveManager: desde la oleada `rare_from_wave`.
func _roll_rare() -> Dictionary:
	if catalog.rare_upgrades.is_empty():
		return {}
	if WaveManager.current_index + 1 < catalog.rare_from_wave:
		return {}
	if _rng.randf() >= catalog.rare_offer_chance:
		return {}
	var equipped: StringName = _equipped_id()
	var candidates: Array[UpgradeData] = []
	for upgrade: UpgradeData in catalog.rare_upgrades:
		if upgrade == null or not upgrade.fits_weapon(equipped):
			continue
		if UpgradeManager.can_add(upgrade, _rare_scope(upgrade, equipped)):
			candidates.push_back(upgrade)
	if candidates.is_empty():
		return {}
	return _rare_offer(candidates[_rng.randi_range(0, candidates.size() - 1)], equipped)


## Una rara de movilidad o de supervivencia es global; una de arma (la que solo
## existe para un arma: el slug, la bala que atraviesa) queda con el arma que la
## compro, como cualquier mejora de arma.
func _rare_offer(upgrade: UpgradeData, equipped: StringName) -> Dictionary:
	var scope: StringName = _rare_scope(upgrade, equipped)
	return {
		"kind": Kind.UPGRADE, "id": upgrade.id, "name": upgrade.display_name,
		"description": upgrade.description, "cost": upgrade.cost,
		"category": int(upgrade.category),
		"owned": UpgradeManager.get_stacks(upgrade.id, scope),
		"max_stacks": upgrade.max_stacks, "weapon_id": scope, "rare": true,
	}


func _rare_scope(upgrade: UpgradeData, equipped: StringName) -> StringName:
	return equipped if upgrade.category == UpgradeData.Category.WEAPON else &""


func _equipped_id() -> StringName:
	var holder: WeaponHolder = _get_holder()
	if holder == null or holder.current == null or holder.current.data == null:
		return &""
	return holder.current.data.id


func _execute(offer: Dictionary) -> EconomyManager.PurchaseResult:
	match int(offer["kind"]):
		Kind.UPGRADE:
			return _buy_upgrade(offer)
		Kind.WEAPON:
			return _buy_weapon(offer)
	return EconomyManager.PurchaseResult.INVALID


func _buy_upgrade(offer: Dictionary) -> EconomyManager.PurchaseResult:
	var data: UpgradeData = catalog.find_upgrade(offer["id"])
	# Empty for MOBILITY/SURVIVABILITY - try_purchase_upgrade ignores it then.
	var weapon_id: StringName = StringName(offer.get("weapon_id", &""))
	return EconomyManager.try_purchase_upgrade(data, weapon_id)


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


func _build_pool() -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	var holder: WeaponHolder = _get_holder()
	var equipped_id: StringName = (
		holder.current.data.id if holder != null and holder.current != null
			and holder.current.data != null else &"")

	for upgrade: UpgradeData in catalog.upgrades:
		# Null check comes first: reading `category` below to compute the scope would
		# crash on a null catalogue entry, and this runs on every shop open and reroll.
		if upgrade == null:
			continue
		# A WEAPON upgrade is scoped to whatever is equipped right now - it is
		# offered/maxed-out per weapon, not once for the whole run.
		var scope: StringName = equipped_id if upgrade.category == UpgradeData.Category.WEAPON \
			else &""
		if not UpgradeManager.can_add(upgrade, scope):
			continue  # Maxed out for this scope: never offered.
		pool.push_back({
			"kind": Kind.UPGRADE, "id": upgrade.id, "name": upgrade.display_name,
			"description": upgrade.description, "cost": upgrade.cost,
			"category": int(upgrade.category),
			"owned": UpgradeManager.get_stacks(upgrade.id, scope),
			"max_stacks": upgrade.max_stacks,
			"weapon_id": scope,
		})

	# En el modo de un arma sola la tienda no vende armas: el arma se eligio en el
	# menu y es la de toda la run.
	var sells_weapons: bool = GameManager.shop_sells_weapons()
	for weapon: WeaponData in catalog.weapons:
		if not sells_weapons:
			break
		if weapon == null or (holder != null and holder.owns(weapon.id)):
			continue  # Never offer the weapon already equipped.
		# Replacing the current weapon leaves its WEAPON upgrades behind - the
		# shop card has to say so before the player spends money on a surprise.
		var replaces: String = (
			" Replaces your current weapon; its upgrades stay behind."
				if holder != null and holder.current != null else "")
		pool.push_back({
			"kind": Kind.WEAPON, "id": weapon.id, "name": weapon.display_name,
			"description": "New weapon.%s" % replaces,
			"cost": catalog.get_weapon_price(weapon.id),
			"category": -1, "owned": 0, "max_stacks": 1,
		})

	return pool


func _get_player() -> Player:
	if _player == null or not is_instance_valid(_player):
		_player = Players.local() as Player
	return _player


func _get_holder() -> WeaponHolder:
	var player: Player = _get_player()
	return player.weapon_holder if player != null else null


