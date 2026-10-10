extends GutTest
## Curarse y las mejoras raras.
##
## La curacion llega por dos caminos: la mejora de regeneracion de la tienda y el
## botiquin que tira el publico. Las raras agregan una regla cada una; todas son
## StatModifiers sobre stats de base neutra, asi que lo que se prueba es que
## comprarlas enciende la regla y que sin comprarlas no pasa nada.

const PLAYER_SCENE: String = "res://scenes/player/player.tscn"
const DROP_SCENE: String = "res://scenes/arena/crowd_drop_pickup.tscn"
const CATALOG_PATH: String = "res://data/economy/shop_catalog.tres"


func before_each() -> void:
	UpgradeManager.reset()
	WaveManager.current_index = -1


func after_each() -> void:
	UpgradeManager.reset()
	WaveManager.current_index = -1
	ObjectPool.release_all()


func _player() -> Player:
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child_autofree(player)
	return player


func _buy(id: String) -> void:
	assert_true(UpgradeManager.add_upgrade(load("res://data/upgrades/%s.tres" % id)),
		"se compro %s" % id)


# ------------------------------------------------------------------ curacion

func test_without_the_upgrade_nothing_regenerates() -> void:
	var player: Player = _player()
	await wait_physics_frames(1)
	player.health.apply_damage(40.0)
	player.perks._since_damage = 10.0
	player.perks._tick_regen(1.0)
	assert_eq(player.health.current_health, 60.0)


func test_nanoweave_regenerates_only_out_of_combat() -> void:
	var player: Player = _player()
	await wait_physics_frames(1)
	_buy("nanoweave")
	player.health.apply_damage(40.0)
	player.perks._tick_regen(1.0)
	assert_eq(player.health.current_health, 60.0, "recien golpeado no se cura")
	player.perks._since_damage = PlayerPerks.REGEN_DELAY + 0.1
	player.perks._tick_regen(1.0)
	assert_gt(player.health.current_health, 60.0)


func test_nanoweave_is_on_sale() -> void:
	var catalog: ShopCatalog = load(CATALOG_PATH)
	assert_not_null(catalog.find_upgrade(&"nanoweave"))


func test_the_crowd_medkit_heals_on_pickup() -> void:
	var player: Player = _player()
	await wait_physics_frames(1)
	player.health.apply_damage(50.0)
	var pickup := ObjectPool.acquire(load(DROP_SCENE)) as CrowdDropPickup
	pickup.data = load("res://data/utilities/medkit.tres")
	pickup._set_available(true)
	assert_true(pickup.collect(player))
	assert_gt(player.health.current_health, 50.0)


func test_a_full_health_player_leaves_the_medkit_on_the_floor() -> void:
	var player: Player = _player()
	await wait_physics_frames(1)
	var pickup := ObjectPool.acquire(load(DROP_SCENE)) as CrowdDropPickup
	pickup.data = load("res://data/utilities/medkit.tres")
	pickup._set_available(true)
	assert_false(pickup.collect(player))
	assert_true(pickup.is_available)


func test_the_crowd_only_throws_a_medkit_to_someone_hurt() -> void:
	var player: Player = _player()
	await wait_physics_frames(1)
	var director := CrowdDropDirector.new()
	add_child_autofree(director)
	var medkit: UtilityData = load("res://data/utilities/medkit.tres")
	assert_false(director._has_room_for(medkit, player))
	player.health.apply_damage(50.0)
	assert_true(director._has_room_for(medkit, player))


# ------------------------------------------------------------------ raras en la tienda

func _shop() -> Shop:
	var shop := Shop.new()
	shop.catalog = load(CATALOG_PATH)
	add_child_autofree(shop)
	return shop


func _rares(offers: Array[Dictionary]) -> int:
	var count: int = 0
	for offer: Dictionary in offers:
		if bool(offer.get("rare", false)):
			count += 1
	return count


func test_the_first_shop_never_offers_a_rare() -> void:
	var shop: Shop = _shop()
	WaveManager.current_index = 0
	for i: int in 30:
		shop.roll_offers()
		assert_eq(_rares(shop.offers), 0)


func test_later_shops_offer_at_most_one_rare() -> void:
	var shop: Shop = _shop()
	WaveManager.current_index = 4
	var seen: int = 0
	for i: int in 60:
		shop.roll_offers()
		assert_lte(_rares(shop.offers), 1)
		seen += _rares(shop.offers)
		assert_lte(shop.offers.size(), shop.catalog.offers_per_visit + 1)
	assert_gt(seen, 0, "en sesenta visitas aparece alguna")


func test_every_rare_upgrade_is_global_and_rare() -> void:
	var catalog: ShopCatalog = load(CATALOG_PATH)
	assert_gt(catalog.rare_upgrades.size(), 0)
	for upgrade: UpgradeData in catalog.rare_upgrades:
		assert_true(upgrade.is_rare, String(upgrade.id))
		assert_ne(upgrade.category, UpgradeData.Category.WEAPON,
			"%s no puede quedar atada a un arma" % upgrade.id)


# ------------------------------------------------------------------ las reglas

func test_air_ace_hits_harder_in_the_air() -> void:
	var player: Player = _player()
	await wait_physics_frames(2)
	var weapon: WeaponComponent = player.weapon
	var grounded: float = weapon.get_damage()
	_buy("air_ace")
	# Recien spawneado y sin piso debajo, el cuerpo esta en el aire.
	if player.is_on_floor():
		pass_test("el jugador quedo apoyado en algo; no se puede medir aca")
		return
	assert_almost_eq(weapon.get_damage(), grounded * 1.25, 0.01)


func test_headhunter_refunds_rounds_on_a_headshot_kill() -> void:
	var player: Player = _player()
	await wait_physics_frames(1)
	_buy("headhunter")
	var weapon: WeaponComponent = player.weapon
	weapon._ammo = 1
	EventBus.kill_scored.emit(&"rusher", Vector3.ZERO, true, 10)
	assert_eq(weapon.get_ammo(), 3)
	EventBus.kill_scored.emit(&"rusher", Vector3.ZERO, false, 10)
	assert_eq(weapon.get_ammo(), 3, "una kill al cuerpo no devuelve nada")


func test_slide_loader_only_reloads_while_sliding() -> void:
	var player: Player = _player()
	await wait_physics_frames(1)
	_buy("slide_loader")
	var weapon: WeaponComponent = player.weapon
	weapon._ammo = 0
	player.perks._tick_slide_loader(1.0)
	assert_eq(weapon.get_ammo(), 0, "parado no recarga")
	player.movement.state = MovementComponent.State.SLIDING
	player.perks._tick_slide_loader(1.0)
	assert_gt(weapon.get_ammo(), 0)


func test_momentum_plating_scales_with_speed() -> void:
	var player: Player = _player()
	await wait_physics_frames(1)
	_buy("momentum_plating")
	player.velocity = Vector3.ZERO
	assert_eq(player.perks._incoming_scale(), 1.0, "quieto, entero")
	player.velocity = Vector3(player.movement.bhop_max_speed, 0.0, 0.0)
	assert_almost_eq(player.perks._incoming_scale(), 0.65, 0.001)


func test_second_wind_saves_one_lethal_hit() -> void:
	var player: Player = _player()
	await wait_physics_frames(1)
	_buy("second_wind")
	player.health.apply_damage(500.0)
	assert_false(player.health.is_dead, "el primer golpe letal no mata")
	assert_eq(player.health.current_health, 1.0)
	player.health.is_invulnerable = false
	player.health.apply_damage(500.0)
	assert_true(player.health.is_dead, "el segundo si")


func test_without_second_wind_a_lethal_hit_kills() -> void:
	var player: Player = _player()
	await wait_physics_frames(1)
	player.health.apply_damage(500.0)
	assert_true(player.health.is_dead)


func test_pad_charger_gives_a_dash_back() -> void:
	var charges := DashCharges.new()
	charges.setup(2, 5.0)
	charges.try_consume()
	assert_eq(charges.get_available(), 1)
	assert_true(charges.restore_one())
	assert_eq(charges.get_available(), 2)
	assert_false(charges.restore_one(), "lleno no hay nada que devolver")


func test_showman_multiplies_style() -> void:
	var before: float = EconomyManager.get_style_multiplier()
	_buy("showman")
	assert_almost_eq(EconomyManager.get_style_multiplier(), before * 1.5, 0.001)
