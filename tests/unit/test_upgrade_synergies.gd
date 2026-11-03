extends GutTest
## Las etiquetas de las mejoras y las raras que escalan con ellas: la sinergia
## (cuantas mas de una familia, mas paga) y la anti-sinergia (otra familia cobra).

const CATALOG_PATH: String = "res://data/economy/shop_catalog.tres"


func before_each() -> void:
	UpgradeManager.reset()


func after_each() -> void:
	UpgradeManager.reset()


func _tagged(id: StringName, tags: Array[StringName],
		category: UpgradeData.Category = UpgradeData.Category.MOBILITY) -> UpgradeData:
	var upgrade := UpgradeData.new()
	upgrade.id = id
	upgrade.category = category
	upgrade.max_stacks = 3
	upgrade.tags = tags
	return upgrade


func _per_tag(id: StringName, stat: StringName, tag: StringName, value: float,
		penalty: bool = false) -> UpgradeData:
	var modifier := StatModifier.new()
	modifier.stat_key = stat
	modifier.operation = StatModifier.Operation.ADD
	modifier.value = value
	modifier.per_tag = tag
	modifier.per_tag_is_penalty = penalty
	var upgrade := UpgradeData.new()
	upgrade.id = id
	upgrade.category = UpgradeData.Category.MOBILITY
	upgrade.is_rare = true
	upgrade.stat_modifiers = [modifier]
	return upgrade


func _catalog() -> ShopCatalog:
	return load(CATALOG_PATH) as ShopCatalog


# ------------------------------------------------------------------ el mecanismo

func test_a_per_tag_modifier_does_nothing_without_the_tag() -> void:
	UpgradeManager.add_upgrade(_per_tag(&"aerialist", &"airborne_damage_multiplier", &"air", 0.1))
	assert_eq(UpgradeManager.get_stat(&"airborne_damage_multiplier", 1.0), 1.0)


func test_a_per_tag_modifier_counts_every_stack_of_the_tag() -> void:
	UpgradeManager.add_upgrade(_per_tag(&"aerialist", &"airborne_damage_multiplier", &"air", 0.1))
	var jump: UpgradeData = _tagged(&"jump", [&"air"] as Array[StringName])
	UpgradeManager.add_upgrade(jump)
	UpgradeManager.add_upgrade(jump)
	UpgradeManager.add_upgrade(_tagged(&"glide", [&"air", &"momentum"] as Array[StringName]))
	assert_almost_eq(UpgradeManager.get_stat(&"airborne_damage_multiplier", 1.0), 1.3, 0.001)
	assert_eq(UpgradeManager.count_tag(&"air"), 3)


func test_buying_into_the_tag_later_still_counts() -> void:
	UpgradeManager.add_upgrade(_tagged(&"jump", [&"air"] as Array[StringName]))
	UpgradeManager.add_upgrade(_per_tag(&"aerialist", &"airborne_damage_multiplier", &"air", 0.1))
	assert_almost_eq(UpgradeManager.get_stat(&"airborne_damage_multiplier", 1.0), 1.1, 0.001)
	UpgradeManager.add_upgrade(_tagged(&"glide", [&"air"] as Array[StringName]))
	assert_almost_eq(UpgradeManager.get_stat(&"airborne_damage_multiplier", 1.0), 1.2, 0.001,
		"la cache se invalida con cada compra")


func test_a_weapon_tag_only_counts_for_its_weapon() -> void:
	UpgradeManager.add_upgrade(_per_tag(&"deadeye", &"headshot_damage_multiplier", &"precision",
		0.1))
	var steady: UpgradeData = _tagged(&"steady", [&"precision"] as Array[StringName],
		UpgradeData.Category.WEAPON)
	UpgradeManager.add_upgrade(steady, &"rifle_ak")
	assert_eq(UpgradeManager.count_tag(&"precision", &"rifle_ak"), 1)
	assert_eq(UpgradeManager.count_tag(&"precision", &"smg"), 0)
	assert_almost_eq(UpgradeManager.get_stat(&"headshot_damage_multiplier", 1.0, &"rifle_ak"),
		1.1, 0.001)
	assert_eq(UpgradeManager.get_stat(&"headshot_damage_multiplier", 1.0, &"smg"), 1.0)


func test_the_shop_names_what_an_offer_feeds_and_what_it_hurts() -> void:
	UpgradeManager.add_upgrade(_per_tag(&"aerialist", &"airborne_damage_multiplier", &"air", 0.1))
	UpgradeManager.add_upgrade(_per_tag(&"bulwark", &"move_speed", &"momentum", -0.3, true))
	var both: UpgradeData = _tagged(&"glide", [&"air", &"momentum"] as Array[StringName])
	var links: Array[Dictionary] = UpgradeManager.get_synergy_links(both)
	assert_eq(links.size(), 2)
	var by_id: Dictionary = {}
	for link: Dictionary in links:
		by_id[link["id"]] = link["penalty"]
	assert_eq(by_id[&"aerialist"], false, "alimenta al Aerialist")
	assert_eq(by_id[&"bulwark"], true, "le cobra al Bulwark")


# ------------------------------------------------------------------ el contenido

func test_every_common_upgrade_has_at_least_one_tag() -> void:
	for upgrade: UpgradeData in _catalog().upgrades:
		if upgrade.is_temporary:
			continue
		assert_false(upgrade.tags.is_empty(), "%s sin etiqueta" % upgrade.id)


func test_every_tag_in_the_content_is_a_known_tag() -> void:
	var catalog: ShopCatalog = _catalog()
	for upgrade: UpgradeData in catalog.upgrades + catalog.rare_upgrades:
		for tag: StringName in upgrade.tags:
			assert_true(UpgradeData.TAG_LABELS.has(tag), "%s: etiqueta '%s'" % [upgrade.id, tag])
		for modifier: StatModifier in upgrade.stat_modifiers:
			if modifier.per_tag != &"":
				assert_true(UpgradeData.TAG_LABELS.has(modifier.per_tag),
					"%s escala con '%s'" % [upgrade.id, modifier.per_tag])


## Una rara de sinergia sin con que alimentarse no se puede comprar con sentido:
## cada etiqueta que escala tiene que tener al menos tres comunes detras.
func test_every_synergy_rare_has_commons_to_feed_it() -> void:
	var catalog: ShopCatalog = _catalog()
	for rare: UpgradeData in catalog.rare_upgrades:
		for modifier: StatModifier in rare.stat_modifiers:
			if modifier.per_tag == &"":
				continue
			var feeders: int = 0
			for upgrade: UpgradeData in catalog.upgrades:
				if upgrade.tags.has(modifier.per_tag):
					feeders += 1
			assert_gte(feeders, 3, "%s escala con %s" % [rare.id, modifier.per_tag])


func test_the_synergy_rares_are_in_the_shop() -> void:
	var ids: Array[StringName] = []
	for rare: UpgradeData in _catalog().rare_upgrades:
		ids.append(rare.id)
	for id: StringName in [&"aerialist", &"deadeye", &"streamliner", &"bulwark"]:
		assert_true(ids.has(id), "%s en rare_upgrades" % id)


func test_a_synergy_rare_does_not_feed_itself() -> void:
	for rare: UpgradeData in _catalog().rare_upgrades:
		for modifier: StatModifier in rare.stat_modifiers:
			if modifier.per_tag != &"":
				assert_false(rare.tags.has(modifier.per_tag), "%s se contaria a si misma" % rare.id)


func test_headshot_damage_reads_the_new_stat() -> void:
	var deadeye: UpgradeData = _per_tag(&"deadeye", &"headshot_damage_multiplier", &"precision",
		0.5)
	deadeye.category = UpgradeData.Category.WEAPON
	UpgradeManager.add_upgrade(deadeye, &"rifle_ak")
	UpgradeManager.add_upgrade(_tagged(&"steady", [&"precision"] as Array[StringName]))
	var data := WeaponData.new()
	data.id = &"rifle_ak"
	data.headshot_multiplier = 2.0
	assert_almost_eq(WeaponComponent.headshot_multiplier_for(data), 3.0, 0.001)


func test_an_offer_carries_its_tags_links_and_scaling() -> void:
	UpgradeManager.add_upgrade(_per_tag(&"aerialist", &"airborne_damage_multiplier", &"air", 0.1))
	UpgradeManager.add_upgrade(_tagged(&"jump", [&"air"] as Array[StringName]))
	var glide: UpgradeData = _tagged(&"glide", [&"air"] as Array[StringName])
	var fields: Dictionary = Shop.synergy_fields(glide, &"")
	assert_eq(String(fields["tags"]), "AIR")
	assert_eq((fields["links"] as Array).size(), 1)
	var rare: UpgradeData = _per_tag(&"aerialist_2", &"airborne_damage_multiplier", &"air", 0.1)
	assert_eq(String(Shop.synergy_fields(rare, &"")["scaling"]), "AIR x1",
		"la rara dice cuanto de su familia ya hay")
