extends GutTest
## The bonus readout the O panel and the shop share.


func _upgrade(id: StringName, category: UpgradeData.Category, stacks: int = 1) -> UpgradeData:
	var data := UpgradeData.new()
	data.id = id
	data.display_name = String(id)
	data.category = category
	data.max_stacks = stacks
	return data


func before_each() -> void:
	UpgradeManager.reset()


func after_all() -> void:
	UpgradeManager.reset()


func test_entries_carry_stacks_and_weapon_scope() -> void:
	var magazine: UpgradeData = _upgrade(&"magazine", UpgradeData.Category.WEAPON, 2)
	UpgradeManager.add_upgrade(magazine, &"smg")
	UpgradeManager.add_upgrade(magazine, &"smg")
	UpgradeManager.add_upgrade(_upgrade(&"move_speed", UpgradeData.Category.MOBILITY),
		&"")

	var entries: Array[Dictionary] = UpgradeManager.get_owned_entries()
	assert_eq(entries.size(), 2, "two distinct purchases, not three")
	for entry: Dictionary in entries:
		if (entry["data"] as UpgradeData).id == &"magazine":
			assert_eq(entry["stacks"], 2)
			assert_eq(entry["weapon_id"], &"smg", "weapon upgrades keep their gun")
		else:
			assert_eq(entry["weapon_id"], &"", "global upgrades are unscoped")


func test_the_same_upgrade_on_two_weapons_stays_separate() -> void:
	var magazine: UpgradeData = _upgrade(&"magazine", UpgradeData.Category.WEAPON)
	UpgradeManager.add_upgrade(magazine, &"smg")
	UpgradeManager.add_upgrade(magazine, &"rifle")
	assert_eq(UpgradeManager.get_owned_entries().size(), 2)


func test_the_list_groups_by_category() -> void:
	UpgradeManager.add_upgrade(_upgrade(&"move_speed", UpgradeData.Category.MOBILITY))
	UpgradeManager.add_upgrade(_upgrade(&"armour", UpgradeData.Category.SURVIVABILITY))
	var list := BonusList.new()
	add_child_autofree(list)
	list.refresh()

	var sections: int = 0
	for child: Node in list.get_children():
		if child is VBoxContainer:
			sections += 1
	assert_eq(sections, 2, "one section per non-empty category, weapon left out")


func test_an_empty_list_says_so() -> void:
	var list := BonusList.new()
	add_child_autofree(list)
	list.refresh()
	var label := list.get_child(0) as Label
	assert_not_null(label)
	assert_eq(label.text, BonusList.EMPTY_TEXT)


func test_the_shop_variant_keeps_every_category() -> void:
	var list := BonusList.new()
	list.show_empty_categories = true
	add_child_autofree(list)
	list.refresh()
	var sections: int = 0
	for child: Node in list.get_children():
		if child is VBoxContainer:
			sections += 1
	assert_eq(sections, BonusList.CATEGORY_ORDER.size(),
		"the shop columns stay put between visits")
