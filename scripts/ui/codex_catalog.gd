class_name CodexCatalog
extends RefCounted
## Lo que muestra el codex: cada cosa del juego que el jugador puede encontrarse,
## en fichas armadas desde los mismos `.tres` que usa el juego.
##
## No hay una lista propia del codex a proposito. Las armas salen del catalogo de
## la tienda, los enemigos de las oleadas, los gadgets de la tabla del publico, y
## asi: un `.tres` nuevo en cualquiera de esos pozos aparece aca sin tocar nada, y
## lo que se saca del juego se va del codex en el mismo commit. Una lista aparte
## seria una tercera copia que se olvida de actualizar.
##
## Separado del panel para que las pruebas puedan leer las fichas sin levantar
## una pantalla. Cada ficha es un Dictionary:
##   id, name, tag (la linea chica de arriba), accent (Color), body, tip,
##   tip_title, stats (Array de [etiqueta, valor]), icon_kind (MayhemIcon.Kind),
##   icon_group e icon_id (IconSet; vacios si el icono es geometria).

const SHOP_CATALOG_PATH: String = "res://data/economy/shop_catalog.tres"
const DROP_TABLE_PATH: String = "res://data/crowd_drop_table.tres"
const ATTACHMENT_CATALOG_PATH: String = "res://data/attachments/attachment_catalog.tres"
const RULE_POOL_PATH: String = "res://data/broadcast_rules/rule_pool.tres"
const REQUEST_POOL_PATH: String = "res://data/crowd_requests/request_pool.tres"
const ECONOMY_CONFIG_PATH: String = "res://data/economy/economy_config.tres"
## El script y no el autoload: los nombres y las explicaciones de los bonos son
## estaticos, y llamarlos por la instancia es un warning.
const KillBonus := preload("res://scripts/autoload/kill_bonus_tracker.gd")
## Las oleadas por numero, como las arma game.tscn. El codex lee de aca que
## enemigos existen: uno que ninguna ola trae no se puede
## encontrar, y una ficha de algo que no se ve confunde mas de lo que explica.
const WAVE_PATH_FORMAT: String = "res://data/waves/wave_%02d.tres"

## Las pestañas, en el orden en que el jugador se las cruza en una run.
const SECTION_WEAPONS: StringName = &"weapons"
const SECTION_UPGRADES: StringName = &"upgrades"
const SECTION_RARES: StringName = &"rares"
const SECTION_GADGETS: StringName = &"gadgets"
const SECTION_ENEMIES: StringName = &"enemies"
const SECTION_ATTACHMENTS: StringName = &"attachments"
const SECTION_RULES: StringName = &"rules"
const SECTION_CROWD: StringName = &"crowd"
const SECTION_STYLE: StringName = &"style"

const CATEGORY_NAME: Dictionary = {
	UpgradeData.Category.MOBILITY: "MOBILITY",
	UpgradeData.Category.WEAPON: "WEAPON",
	UpgradeData.Category.SURVIVABILITY: "SURVIVABILITY",
}

const CATEGORY_KEY: Dictionary = {
	UpgradeData.Category.MOBILITY: "mobility",
	UpgradeData.Category.WEAPON: "weapon",
	UpgradeData.Category.SURVIVABILITY: "survivability",
}


## Todas las pestañas: {id, title, entries}. Una pestaña sin fichas no se
## devuelve, para no mostrar una pagina vacia.
static func sections() -> Array[Dictionary]:
	var shop: ShopCatalog = load(SHOP_CATALOG_PATH) as ShopCatalog
	var all: Array[Dictionary] = [
		_section(SECTION_WEAPONS, "WEAPONS", weapon_entries(shop)),
		_section(SECTION_UPGRADES, "UPGRADES", upgrade_entries(shop, false)),
		_section(SECTION_RARES, "RARES", upgrade_entries(shop, true)),
		_section(SECTION_GADGETS, "GADGETS", gadget_entries()),
		_section(SECTION_ENEMIES, "ENEMIES", enemy_entries()),
		_section(SECTION_ATTACHMENTS, "ATTACHMENTS", attachment_entries(shop)),
		_section(SECTION_RULES, "HOUSE RULES", rule_entries()),
		_section(SECTION_CROWD, "CROWD", request_entries()),
		_section(SECTION_STYLE, "STYLE", bonus_entries()),
	]
	var result: Array[Dictionary] = []
	for section: Dictionary in all:
		if not (section["entries"] as Array).is_empty():
			result.append(section)
	return result


## Daño por segundo sosteniendo el gatillo, sin recargas ni caida por distancia:
## el numero que se compara entre armas, no el que se hace en una pelea.
static func weapon_dps(weapon: WeaponData) -> float:
	return weapon.damage * float(weapon.projectiles_per_shot) * weapon.fire_rate


static func weapon_entries(shop: ShopCatalog) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if shop == null:
		return entries
	for weapon: WeaponData in shop.weapons:
		if weapon == null:
			continue
		var damage: String = "%d" % roundi(weapon.damage)
		if weapon.projectiles_per_shot > 1:
			damage = "%d x %d pellets" % [roundi(weapon.damage), weapon.projectiles_per_shot]
		var stats: Array = [
			["DAMAGE PER SECOND", "%d" % roundi(weapon_dps(weapon))],
			["DAMAGE", damage],
			["FIRE RATE", "%.1f / s" % weapon.fire_rate],
			["MAGAZINE", "%d" % weapon.magazine_size],
			["RELOAD", "%.1f s" % weapon.reload_time],
			["FULL DAMAGE UP TO", "%d m" % roundi(weapon.falloff_start)],
			["HEADSHOT", "x%.1f" % weapon.headshot_multiplier],
		]
		if weapon.pierce_count > 0:
			stats.append(["PIERCES", "%d enemies" % weapon.pierce_count])
		if weapon.splash_radius > 0.0:
			stats.append(["SPLASH", "%.1f m" % weapon.splash_radius])
		var price: int = shop.get_weapon_price(weapon.id)
		if price > 0:
			stats.append(["ARSENAL PRICE", "%d" % price])
		if Armory.catalog != null and Armory.catalog.max_level() > 0:
			stats.append(["MASTERY", "LEVEL %d / %d" % [Armory.get_level(weapon.id),
				Armory.catalog.max_level()]])
		entries.append(_entry(weapon.id, weapon.display_name, "WEAPON", Tokens.PLAYER,
			weapon.codex_blurb, stats, MayhemIcon.for_weapon(weapon.id)))
	return entries


## Las comunes o las raras. Las comunes van agrupadas por categoria, que es como
## las piensa el jugador ("¿que habia de movilidad?").
static func upgrade_entries(shop: ShopCatalog, rare: bool) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if shop == null:
		return entries
	var list: Array[UpgradeData] = []
	for upgrade: UpgradeData in (shop.rare_upgrades if rare else shop.upgrades):
		if upgrade != null:
			list.append(upgrade)
	list.sort_custom(func(a: UpgradeData, b: UpgradeData) -> bool:
		if a.category != b.category:
			return a.category < b.category
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	for upgrade: UpgradeData in list:
		var category: String = String(CATEGORY_NAME.get(upgrade.category, ""))
		var accent: Color = Tokens.REWARD
		if not rare:
			accent = Tokens.CATEGORY_COLOR.get(CATEGORY_KEY.get(upgrade.category, ""), Tokens.TEXT)
		var stats: Array = [["COST", "%d" % upgrade.cost]]
		if upgrade.max_stacks > 1:
			stats.append(["STACKS", "up to %d" % upgrade.max_stacks])
		if upgrade.is_temporary and upgrade.duration > 0.0:
			stats.append(["LASTS", "%d s" % roundi(upgrade.duration)])
		if not upgrade.weapon_ids.is_empty():
			stats.append(["ONLY WITH", _weapon_names(shop, upgrade.weapon_ids)])
		if not upgrade.tags.is_empty():
			stats.append(["FAMILY", upgrade.get_tag_text()])
		var scaling: PackedStringArray = PackedStringArray()
		for tag: StringName in upgrade.get_scaling_tags():
			scaling.append(String(UpgradeData.TAG_LABELS.get(tag, String(tag).to_upper())))
		if not scaling.is_empty():
			stats.append(["SCALES WITH", " · ".join(scaling)])
		if rare:
			stats.append(["OFFERED", "From wave %d, at most one per visit" % shop.rare_from_wave])
		var entry: Dictionary = _entry(upgrade.id, upgrade.display_name,
			"RARE  -  NEW RULE" if rare else category, accent, upgrade.description, stats)
		entry["icon_group"] = IconSet.UPGRADE
		entry["icon_id"] = upgrade.id
		entries.append(entry)
	return entries


static func gadget_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var table: CrowdDropTable = load(DROP_TABLE_PATH) as CrowdDropTable
	if table == null:
		return entries
	for gadget: UtilityData in table.utilities:
		if gadget == null:
			continue
		var stats: Array = []
		if gadget.effect_radius > 0.0:
			stats.append(["RADIUS", "%.1f m" % gadget.effect_radius])
		if gadget.effect_duration > 0.0:
			stats.append(["LASTS", "%.1f s" % gadget.effect_duration])
		if gadget.cooldown > 0.0:
			stats.append(["COOLDOWN", "%d s" % roundi(gadget.cooldown)])
		if gadget.max_carried > 0:
			stats.append(["CARRY", "up to %d" % gadget.max_carried])
		stats.append(["HOW TO GET IT", "The crowd throws it into the arena during a wave"])
		entries.append(_entry(gadget.id, gadget.display_name,
			"GADGET  -  %s" % gadget.tag if not gadget.tag.is_empty() else "GADGET",
			gadget.accent_color, gadget.summary, stats, MayhemIcon.for_utility(gadget.id)))
	return entries


## En el orden en que aparecen en la run.
static func enemy_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var debut: Dictionary = enemy_debuts()
	var enemies: Array[EnemyData] = []
	for enemy: EnemyData in debut.keys():
		enemies.append(enemy)
	enemies.sort_custom(func(a: EnemyData, b: EnemyData) -> bool:
		return int(debut[a]) < int(debut[b]))
	for enemy: EnemyData in enemies:
		var stats: Array = [
			["HEALTH", "%d" % roundi(enemy.max_health)],
			["SPEED", "%.1f m/s" % enemy.move_speed],
		]
		if enemy.damage > 0.0:
			stats.append(["DAMAGE", "%d" % roundi(enemy.damage)])
		# Por debajo de esto es cuerpo a cuerpo y el numero no dice nada.
		if enemy.attack_range > 4.0:
			stats.append(["ATTACKS FROM", "%d m" % roundi(enemy.attack_range)])
		stats.append(["REWARD", "%d" % enemy.reward_currency])
		stats.append(["FIRST SEEN", "Wave %d" % int(debut[enemy])])
		var entry: Dictionary = _entry(enemy.id, enemy.display_name, "ENEMY",
			enemy.body_color, enemy.codex_blurb, stats)
		entry["tip"] = enemy.codex_tip
		entry["tip_title"] = "HOW TO BEAT IT"
		entry["icon_group"] = IconSet.ENEMY
		entry["icon_id"] = enemy.id
		entries.append(entry)
	return entries


## Cada arquetipo que alguna oleada trae, con la primera ola en la que aparece.
## Por id y no por instancia: dos `.tres` del mismo arquetipo serian una ficha.
static func enemy_debuts() -> Dictionary:
	var by_id: Dictionary = {}
	var result: Dictionary = {}
	for wave_number: int in range(1, WaveManager.WAVE_COUNT + 1):
		var wave: WaveData = load(WAVE_PATH_FORMAT % wave_number) as WaveData
		if wave == null:
			continue
		for group: SpawnGroup in wave.spawn_groups:
			if group == null or group.enemy_data == null or by_id.has(group.enemy_data.id):
				continue
			by_id[group.enemy_data.id] = true
			result[group.enemy_data] = wave_number
	return result


static func attachment_entries(shop: ShopCatalog) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var catalog: AttachmentCatalog = load(ATTACHMENT_CATALOG_PATH) as AttachmentCatalog
	if catalog == null:
		return entries
	for attachment: AttachmentData in catalog.attachments:
		if attachment == null:
			continue
		var weapon: String = _weapon_names(shop, [attachment.weapon_id])
		var slot: String = String(AttachmentData.SLOT_LABEL.get(attachment.slot, ""))
		var stats: Array = [
			["WEAPON", weapon],
			["SLOT", slot],
			["UNLOCKS AT", "Mastery level %d" % attachment.unlock_level],
			["WHERE", "Armory, before a run. Kept between runs"],
		]
		entries.append(_entry(attachment.id, attachment.display_name,
			"%s  -  %s" % [weapon.to_upper(), slot], Tokens.PLAYER, attachment.description,
			stats, MayhemIcon.for_weapon(attachment.weapon_id)))
	return entries


## Las reglas de la casa y despues los contratos: las dos cosas que el Host ofrece
## en la tienda.
static func rule_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var pool: BroadcastRulePool = load(RULE_POOL_PATH) as BroadcastRulePool
	if pool == null:
		return entries
	for rule: BroadcastRule in pool.rules:
		if rule == null:
			continue
		var when: String = "From wave %d" % pool.from_wave
		if pool.skip_elite_waves:
			when += ", not on the big waves"
		entries.append(_entry(rule.id, _title_case(rule.title), "HOUSE RULE", Tokens.HAZARD,
			rule.description, [["OFFERED", when], ["LASTS", "One wave"]]))
	for contract: BroadcastRule in pool.contracts:
		if contract == null:
			continue
		var pays: String = "%d" % contract.contract_payout
		if contract.contract_payout_per_wave > 0:
			pays += " + %d per wave" % contract.contract_payout_per_wave
		entries.append(_entry(contract.id, _title_case(contract.title), "CONTRACT",
			Tokens.REWARD, contract.description, [
				["PAYS", pays + ", if you clear the wave"],
				["OFFERED", "From wave %d. Optional: you sign it or not" % pool.contracts_from_wave],
			]))
	return entries


static func request_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var pool: CrowdRequestPool = load(REQUEST_POOL_PATH) as CrowdRequestPool
	if pool == null:
		return entries
	for request: CrowdRequest in pool.requests:
		if request == null:
			continue
		var bonus: String = KillBonus.get_label(request.bonus_id)
		var body: String = "Get %d %s kill%s in %d seconds." % [request.goal, bonus,
			"s" if request.goal != 1 else "", roundi(request.time_limit)]
		var described: String = KillBonus.get_description(request.bonus_id)
		if not described.is_empty():
			body += "\n%s: %s" % [bonus, described]
		var reward: String = "%d" % request.reward_currency
		if request.reward_rating > 0.0:
			reward += " and +%d rating" % roundi(request.reward_rating)
		var stats: Array = [
			["GOAL", "%d kill%s" % [request.goal, "s" if request.goal != 1 else ""]],
			["TIME", "%d s" % roundi(request.time_limit)],
			["REWARD", reward],
		]
		if request.throws_gift:
			stats.append(["GIFT", "The crowd throws a gadget"])
		stats.append(["FROM", "Wave %d" % pool.from_wave])
		entries.append(_entry(request.id, _title_case(request.title), "CROWD REQUEST",
			Tokens.REWARD, body, stats))
	return entries


static func bonus_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var config: EconomyConfig = load(ECONOMY_CONFIG_PATH) as EconomyConfig
	for bonus_id: StringName in KillBonus.BONUS_LABEL.keys():
		var stats: Array = []
		if config != null:
			stats.append(["PAYS", "%d per kill" % config.get_kill_bonus(bonus_id)])
		var entry: Dictionary = _entry(bonus_id, KillBonus.get_label(bonus_id),
			"STYLE BONUS", Tokens.REWARD, KillBonus.get_description(bonus_id), stats)
		entry["icon_group"] = IconSet.BONUS
		entry["icon_id"] = bonus_id
		entries.append(entry)
	return entries


# Private

static func _section(id: StringName, title: String, entries: Array[Dictionary]) -> Dictionary:
	return {"id": id, "title": title, "entries": entries}


static func _entry(id: StringName, entry_name: String, tag: String, accent: Color,
		body: String, stats: Array, icon_kind: MayhemIcon.Kind = MayhemIcon.Kind.NONE) -> Dictionary:
	return {
		"id": id,
		"name": entry_name,
		"tag": tag,
		"accent": accent,
		"body": body,
		"tip": "",
		"tip_title": "",
		"stats": stats,
		"icon_kind": icon_kind,
		"icon_group": &"",
		"icon_id": &"",
	}


static func _weapon_names(shop: ShopCatalog, ids: Array) -> String:
	var names: PackedStringArray = PackedStringArray()
	for id: Variant in ids:
		var found: String = String(id)
		if shop != null:
			for weapon: WeaponData in shop.weapons:
				if weapon != null and weapon.id == StringName(id):
					found = weapon.display_name
		names.append(found)
	return ", ".join(names)


## Los titulos de reglas y pedidos estan en mayusculas porque van a un cartel. En
## una lista, mayusculas en cada fila gritan todas igual.
static func _title_case(text: String) -> String:
	return text.capitalize() if text == text.to_upper() else text
