extends GutTest
## El codex del menu y la pausa: que cada cosa del juego tenga su ficha, y que
## cada ficha diga algo.


func _section(id: StringName) -> Dictionary:
	for section: Dictionary in CodexCatalog.sections():
		if section["id"] == id:
			return section
	return {}


func _ids(section: Dictionary) -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry: Dictionary in section.get("entries", []):
		ids.append(StringName(entry["id"]))
	return ids


func test_every_entry_has_a_name_and_says_what_it_does() -> void:
	for section: Dictionary in CodexCatalog.sections():
		for entry: Dictionary in section["entries"]:
			var where: String = "%s/%s" % [section["id"], entry["id"]]
			assert_ne(String(entry["name"]).strip_edges(), "", "%s sin nombre" % where)
			assert_ne(String(entry["body"]).strip_edges(), "", "%s sin descripcion" % where)


func test_every_weapon_in_the_shop_has_an_entry() -> void:
	var shop: ShopCatalog = load(CodexCatalog.SHOP_CATALOG_PATH) as ShopCatalog
	var ids: Array[StringName] = _ids(_section(CodexCatalog.SECTION_WEAPONS))
	for weapon: WeaponData in shop.weapons:
		assert_has(ids, weapon.id, "%s falta en el codex" % weapon.id)


func test_upgrades_and_rares_go_to_separate_tabs() -> void:
	var shop: ShopCatalog = load(CodexCatalog.SHOP_CATALOG_PATH) as ShopCatalog
	assert_eq(_ids(_section(CodexCatalog.SECTION_UPGRADES)).size(), shop.upgrades.size())
	assert_eq(_ids(_section(CodexCatalog.SECTION_RARES)).size(), shop.rare_upgrades.size())


## Lo que el jugador puede encontrarse, y nada mas: el Elite esta en el banco.
func test_the_enemy_tab_lists_what_the_waves_bring_in_order_of_appearance() -> void:
	var debuts: Dictionary = CodexCatalog.enemy_debuts()
	var entries: Array = _section(CodexCatalog.SECTION_ENEMIES)["entries"]
	assert_eq(entries.size(), debuts.size())
	assert_does_not_have(_ids(_section(CodexCatalog.SECTION_ENEMIES)), &"elite",
		"ninguna ola trae al Elite")
	var last: int = 0
	for entry: Dictionary in entries:
		var wave: int = 0
		for enemy: EnemyData in debuts.keys():
			if enemy.id == entry["id"]:
				wave = int(debuts[enemy])
		assert_true(wave >= last, "%s fuera de orden" % entry["id"])
		last = wave


func test_every_enemy_says_how_to_beat_it() -> void:
	for entry: Dictionary in _section(CodexCatalog.SECTION_ENEMIES)["entries"]:
		assert_ne(String(entry["tip"]).strip_edges(), "", "%s sin consejo" % entry["id"])


func test_every_style_bonus_explains_how_to_earn_it() -> void:
	var ids: Array[StringName] = _ids(_section(CodexCatalog.SECTION_STYLE))
	for bonus_id: StringName in KillBonusTracker.BONUS_LABEL.keys():
		assert_has(ids, bonus_id)
		assert_has(KillBonusTracker.BONUS_DESCRIPTION, bonus_id,
			"%s sin explicacion" % bonus_id)


func test_the_shotgun_counts_every_pellet_in_its_damage_per_second() -> void:
	var weapon := WeaponData.new()
	weapon.damage = 10.0
	weapon.projectiles_per_shot = 9
	weapon.fire_rate = 2.0
	assert_almost_eq(CodexCatalog.weapon_dps(weapon), 180.0, 0.001)


func test_the_panel_opens_on_the_first_entry_and_changes_tab() -> void:
	var panel := CodexPanel.new()
	add_child_autofree(panel)
	panel.open()
	assert_true(panel.visible)
	assert_eq(panel.get_section_count(), CodexCatalog.sections().size())
	var first_name: String = String(CodexCatalog.sections()[0]["entries"][0]["name"])
	var shown: Label = panel.find_child("EntryName", true, false) as Label
	assert_not_null(shown)
	assert_eq(shown.text, first_name)

	panel.show_section(1)
	await wait_process_frames(1)
	shown = panel.find_child("EntryName", true, false) as Label
	assert_eq(shown.text, String(CodexCatalog.sections()[1]["entries"][0]["name"]))


func test_closing_the_panel_says_so() -> void:
	var panel := CodexPanel.new()
	add_child_autofree(panel)
	panel.open()
	watch_signals(panel)
	panel.close()
	assert_false(panel.visible)
	assert_signal_emitted(panel, "closed")
