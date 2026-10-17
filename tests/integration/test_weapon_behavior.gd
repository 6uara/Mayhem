extends GutTest
## Lo que hace un tiro ademas de pegar donde apunta: atravesar, salpicar, empujar.
## Apagado en las cuatro armas; lo prenden las mejoras raras de cada una.
##
## Se dispara de verdad contra muñecos puestos en fila delante del jugador, sin
## dispersion (una mejora global la pisa a cero) para que el resultado no dependa
## del azar del cono.

const PLAYER_SCENE: String = "res://scenes/player/player.tscn"
const DUMMY_SCENE: String = "res://scenes/enemies/target_dummy.tscn"
const SHOP_CATALOG_PATH: String = "res://data/economy/shop_catalog.tres"
## El centro del hitbox de cuerpo del muñeco, sobre sus pies.
const DUMMY_CHEST: float = 0.7


func before_each() -> void:
	UpgradeManager.reset()
	var steady := UpgradeData.new()
	steady.id = &"test_no_spread"
	steady.category = UpgradeData.Category.MOBILITY
	var modifier := StatModifier.new()
	modifier.stat_key = StatsComponent.SPREAD_MULTIPLIER
	modifier.operation = StatModifier.Operation.OVERRIDE
	modifier.value = 0.0
	var modifiers: Array[StatModifier] = [modifier]
	steady.stat_modifiers = modifiers
	UpgradeManager.add_upgrade(steady)


func after_each() -> void:
	UpgradeManager.reset()


func _player() -> Player:
	return add_child_autofree(load(PLAYER_SCENE).instantiate())


## Un muñeco a `distance` metros delante del jugador, corrido `side` metros.
func _dummy(player: Player, distance: float, side: float = 0.0) -> TargetDummy:
	var aim: Node3D = player.weapon.aim_node
	var dummy := add_child_autofree(load(DUMMY_SCENE).instantiate()) as TargetDummy
	dummy.global_position = aim.global_position - aim.global_transform.basis.z * distance \
		+ aim.global_transform.basis.x * side + Vector3.DOWN * DUMMY_CHEST
	return dummy


func _give(weapon: WeaponComponent, key: StringName, operation: StatModifier.Operation,
		value: float) -> void:
	var upgrade := UpgradeData.new()
	upgrade.id = StringName("test_%s" % key)
	upgrade.category = UpgradeData.Category.WEAPON
	var modifier := StatModifier.new()
	modifier.stat_key = key
	modifier.operation = operation
	modifier.value = value
	var modifiers: Array[StatModifier] = [modifier]
	upgrade.stat_modifiers = modifiers
	UpgradeManager.add_upgrade(upgrade, weapon.data.id)


func _fire(weapon: WeaponComponent) -> void:
	weapon._cooldown = 0.0
	weapon.is_reloading = false
	weapon._try_fire()


func _hurt(dummy: TargetDummy) -> bool:
	return dummy.health.current_health < dummy.health.max_health


# ------------------------------------------------------------------ perforar

func test_a_plain_round_stops_at_the_first_body() -> void:
	var player: Player = _player()
	await wait_physics_frames(2)
	var front: TargetDummy = _dummy(player, 5.0)
	var back: TargetDummy = _dummy(player, 8.0)
	await wait_physics_frames(2)
	_fire(player.weapon)
	assert_true(_hurt(front))
	assert_false(_hurt(back))


func test_a_piercing_round_hits_the_ones_behind_for_less() -> void:
	var player: Player = _player()
	await wait_physics_frames(2)
	_give(player.weapon, StatsComponent.PIERCE_COUNT, StatModifier.Operation.ADD, 2.0)
	var dummies: Array[TargetDummy] = [_dummy(player, 5.0), _dummy(player, 8.0),
		_dummy(player, 11.0), _dummy(player, 14.0)]
	await wait_physics_frames(2)
	_fire(player.weapon)
	assert_true(_hurt(dummies[0]))
	assert_true(_hurt(dummies[1]))
	assert_true(_hurt(dummies[2]))
	assert_false(_hurt(dummies[3]), "dos de mas, no tres")
	assert_lt(dummies[0].health.current_health, dummies[1].health.current_health,
		"cada uno que atraviesa le saca fuerza")


# ------------------------------------------------------------------ salpicar

func test_splash_reaches_the_one_standing_next_to_the_target() -> void:
	var player: Player = _player()
	await wait_physics_frames(2)
	_give(player.weapon, StatsComponent.SPLASH_RADIUS, StatModifier.Operation.ADD, 1.5)
	var target: TargetDummy = _dummy(player, 6.0)
	var neighbour: TargetDummy = _dummy(player, 6.0, 1.0)
	var far: TargetDummy = _dummy(player, 6.0, 4.0)
	await wait_physics_frames(2)
	_fire(player.weapon)
	assert_true(_hurt(target))
	assert_true(_hurt(neighbour))
	assert_false(_hurt(far))
	assert_lt(target.health.current_health, neighbour.health.current_health,
		"el area pega menos que el tiro")


func test_no_splash_without_the_upgrade() -> void:
	var player: Player = _player()
	await wait_physics_frames(2)
	_dummy(player, 6.0)
	var neighbour: TargetDummy = _dummy(player, 6.0, 1.0)
	await wait_physics_frames(2)
	_fire(player.weapon)
	assert_false(_hurt(neighbour))


# ------------------------------------------------------------------ empujar

func test_knockback_shoves_the_shooter_against_the_aim() -> void:
	var player: Player = _player()
	await wait_physics_frames(2)
	_give(player.weapon, StatsComponent.SELF_KNOCKBACK, StatModifier.Operation.ADD, 9.0)
	var forward: Vector3 = -player.weapon.aim_node.global_transform.basis.z
	player.velocity = Vector3.ZERO
	_fire(player.weapon)
	assert_almost_eq(player.velocity.dot(forward), -9.0, 0.01)


func test_no_weapon_shoves_by_default() -> void:
	var player: Player = _player()
	await wait_physics_frames(2)
	for weapon: WeaponComponent in player.weapon_holder.get_all():
		assert_eq(weapon.get_self_knockback(), 0.0, String(weapon.data.id))
		assert_eq(weapon.get_pierce_count(), 0, String(weapon.data.id))
		assert_eq(weapon.get_splash_radius(), 0.0, String(weapon.data.id))


# ------------------------------------------------------------------ las raras de cada arma

func _rare(id: StringName) -> UpgradeData:
	return (load(SHOP_CATALOG_PATH) as ShopCatalog).find_upgrade(id)


func test_slug_turns_nine_pellets_into_one() -> void:
	var player: Player = _player()
	await wait_physics_frames(2)
	var shotgun: WeaponComponent = player.weapon_holder.find_by_id(&"shotgun")
	assert_gt(shotgun.get_projectiles_per_shot(), 1)
	UpgradeManager.add_upgrade(_rare(&"slug"), &"shotgun")
	assert_eq(shotgun.get_projectiles_per_shot(), 1)
	var pistol: WeaponComponent = player.weapon_holder.find_by_id(&"pistol")
	assert_eq(pistol.get_projectiles_per_shot(), 1, "y no toca a las otras")


func test_last_word_triples_only_the_last_round() -> void:
	var player: Player = _player()
	await wait_physics_frames(2)
	var pistol: WeaponComponent = player.weapon_holder.find_by_id(&"pistol")
	UpgradeManager.add_upgrade(_rare(&"last_word"), &"pistol")
	pistol._shot_index = 3
	pistol._ammo = 5
	assert_eq(pistol._shot_damage_multiplier(), 1.0)
	pistol._ammo = 0
	assert_eq(pistol._shot_damage_multiplier(), 3.0)


func test_marksman_trigger_doubles_the_first_shot_of_a_burst() -> void:
	var player: Player = _player()
	await wait_physics_frames(2)
	var rifle: WeaponComponent = player.weapon_holder.find_by_id(&"rifle_ak")
	UpgradeManager.add_upgrade(_rare(&"marksman_trigger"), &"rifle_ak")
	rifle._ammo = 10
	rifle._shot_index = 0
	assert_eq(rifle._shot_damage_multiplier(), 2.0)
	rifle._shot_index = 1
	assert_eq(rifle._shot_damage_multiplier(), 1.0)


## Sin el piso abajo el jugador esta en el aire, que es la peor penalidad.
func test_run_and_gun_removes_the_movement_penalty() -> void:
	UpgradeManager.reset()
	var player: Player = _player()
	await wait_physics_frames(2)
	var smg: WeaponComponent = player.weapon_holder.find_by_id(&"smg")
	assert_false(player.is_on_floor(), "precondicion: en el aire")
	assert_gt(smg.get_current_spread(), smg.data.spread_hipfire)
	UpgradeManager.add_upgrade(_rare(&"run_and_gun"), &"smg")
	assert_almost_eq(smg.get_current_spread(), smg.data.spread_hipfire, 0.001)


func test_a_weapon_rare_is_only_offered_with_its_weapon() -> void:
	var catalog: ShopCatalog = load(SHOP_CATALOG_PATH)
	for upgrade: UpgradeData in catalog.rare_upgrades:
		if upgrade.weapon_ids.is_empty():
			continue
		assert_true(upgrade.fits_weapon(upgrade.weapon_ids[0]))
		assert_false(upgrade.fits_weapon(&"not_a_weapon"), String(upgrade.id))


func test_every_weapon_has_its_own_rares() -> void:
	var catalog: ShopCatalog = load(SHOP_CATALOG_PATH)
	for weapon: WeaponData in catalog.weapons:
		var own: int = 0
		for upgrade: UpgradeData in catalog.rare_upgrades:
			if upgrade.weapon_ids.has(weapon.id):
				own += 1
		assert_gte(own, 2, "%s no tiene raras propias" % weapon.id)
