extends GutTest
## La maestria de armas y los attachments: lo unico que se arrastra entre runs.
##
## Lo que se fija: que la experiencia se gana solo jugando una run y se guarda al
## terminarla, que un attachment bloqueado no se puede poner, que hay uno por
## ranura, que lo puesto entra a la run como mejora del arma correcta, y que cada
## attachment cobra algo por lo que da.

const SHOP_CATALOG_PATH: String = "res://data/economy/shop_catalog.tres"
const TEST_PATH: String = "user://armory_unit_test.json"

## Las ranuras cuyo stat lee de verdad un arma: un attachment que mueve otra
## cosa no hace nada.
const WEAPON_STATS: Array[StringName] = [
	StatsComponent.WEAPON_DAMAGE, StatsComponent.FIRE_RATE, StatsComponent.MAGAZINE_SIZE,
	StatsComponent.RESERVE_AMMO_MAX, StatsComponent.RELOAD_TIME,
	StatsComponent.RECOIL_MAGNITUDE, StatsComponent.SPREAD_MULTIPLIER,
	StatsComponent.ADS_TRANSITION_TIME,
]

var _saved_path: String
var _saved_catalog: AttachmentCatalog


func before_each() -> void:
	_saved_path = Armory.save_path
	_saved_catalog = Armory.catalog
	Armory.save_path = TEST_PATH
	Armory.reset_progress()
	UpgradeManager.reset()


func after_each() -> void:
	Armory.reset_progress()
	Armory.save_path = _saved_path
	Armory.catalog = _saved_catalog
	Armory.load_progress()
	UpgradeManager.reset()


func _first(weapon_id: StringName, slot: AttachmentData.Slot) -> AttachmentData:
	for attachment: AttachmentData in Armory.get_attachments(weapon_id):
		if attachment.slot == slot:
			return attachment
	return null


func _play_run(weapon_id: StringName, xp: int, victory: bool = false) -> void:
	Armory.begin_run()
	Armory.add_run_xp(weapon_id, xp)
	EventBus.run_finished.emit(0, 60.0, 1, victory)


# ------------------------------------------------------------------ la experiencia

func test_a_run_levels_up_the_weapon_it_was_played_with() -> void:
	_play_run(&"pistol", Armory.catalog.level_thresholds[0])
	assert_eq(Armory.get_level(&"pistol"), 1)
	assert_eq(Armory.get_level(&"smg"), 0, "las otras armas no se enteran")


func test_xp_outside_a_run_counts_for_nothing() -> void:
	Armory.add_run_xp(&"pistol", 5000)
	EventBus.run_finished.emit(0, 60.0, 1, false)
	assert_eq(Armory.get_xp(&"pistol"), 0)


func test_the_end_of_the_run_says_what_it_unlocked() -> void:
	_play_run(&"pistol", Armory.catalog.level_thresholds[0])
	var report: Array[Dictionary] = Armory.get_last_report()
	assert_eq(report.size(), 1)
	var unlocked: Array = report[0]["unlocked"]
	assert_eq(unlocked.size(), 1)
	assert_eq((unlocked[0] as AttachmentData).unlock_level, 1)
	var lines: Array[String] = load("res://scripts/ui/match_overlay.gd").mastery_lines(report)
	assert_string_contains(lines[0], "UNLOCKED")


func test_the_next_threshold_ends_at_max_level() -> void:
	var thresholds: PackedInt32Array = Armory.catalog.level_thresholds
	assert_eq(Armory.get_next_threshold(&"rifle_ak"), thresholds[0])
	_play_run(&"rifle_ak", thresholds[thresholds.size() - 1])
	assert_eq(Armory.get_next_threshold(&"rifle_ak"), -1)


func test_progress_survives_a_restart() -> void:
	_play_run(&"smg", Armory.catalog.level_thresholds[1])
	var muzzle: AttachmentData = _first(&"smg", AttachmentData.Slot.MUZZLE)
	assert_true(Armory.set_equipped(muzzle, true))
	Armory.load_progress()
	assert_eq(Armory.get_level(&"smg"), 2)
	assert_true(Armory.is_equipped(muzzle))


func test_a_hand_edited_file_keeps_what_makes_sense() -> void:
	var file: FileAccess = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string('{"xp": {"pistol": 400, "smg": "lots", "rifle_ak": -3}, "equipped": {"pistol": ["x", 5]}}')
	file.close()
	Armory.load_progress()
	assert_eq(Armory.get_xp(&"pistol"), 400)
	assert_eq(Armory.get_xp(&"smg"), 0)
	assert_eq(Armory.get_xp(&"rifle_ak"), 0)
	assert_eq(Armory.get_equipped(&"pistol").size(), 0, "ids que no existen no se ponen")


func test_garbage_on_disk_starts_fresh() -> void:
	var file: FileAccess = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("not json at all")
	file.close()
	Armory.load_progress()
	assert_eq(Armory.get_xp(&"pistol"), 0)


# ------------------------------------------------------------------ ponerse cosas

func test_a_locked_attachment_cannot_be_worn() -> void:
	var optic: AttachmentData = _first(&"pistol", AttachmentData.Slot.OPTIC)
	assert_false(Armory.is_unlocked(optic))
	assert_false(Armory.set_equipped(optic, true))
	assert_false(Armory.is_equipped(optic))


func test_one_attachment_per_slot() -> void:
	var catalog := AttachmentCatalog.new()
	catalog.level_thresholds = PackedInt32Array([1])
	var first := AttachmentData.new()
	first.id = &"a"
	first.weapon_id = &"pistol"
	var second := AttachmentData.new()
	second.id = &"b"
	second.weapon_id = &"pistol"
	var list: Array[AttachmentData] = [first, second]
	catalog.attachments = list
	Armory.catalog = catalog
	_play_run(&"pistol", 10)
	Armory.set_equipped(first, true)
	Armory.set_equipped(second, true)
	assert_false(Armory.is_equipped(first), "la misma ranura: entra uno, sale el otro")
	assert_true(Armory.is_equipped(second))


func test_what_is_worn_goes_into_the_run_on_that_weapon_only() -> void:
	_play_run(&"pistol", Armory.catalog.level_thresholds[0])
	var muzzle: AttachmentData = _first(&"pistol", AttachmentData.Slot.MUZZLE)
	Armory.set_equipped(muzzle, true)
	UpgradeManager.reset()
	Armory.begin_run()
	var key: StringName = muzzle.stat_modifiers[0].stat_key
	var on_pistol: float = UpgradeManager.get_stat(key, 1.0, &"pistol")
	assert_ne(on_pistol, 1.0, "el attachment se aplica")
	assert_eq(UpgradeManager.get_stat(key, 1.0, &"smg"), 1.0, "y solo a su arma")
	assert_true(Armory.get_loadout_ids().has(String(muzzle.id)))


# ------------------------------------------------------------------ los datos

func test_every_attachment_belongs_to_a_real_weapon_and_a_reachable_level() -> void:
	var shop: ShopCatalog = load(SHOP_CATALOG_PATH)
	assert_gt(Armory.catalog.attachments.size(), 0)
	for attachment: AttachmentData in Armory.catalog.attachments:
		assert_not_null(shop.find_weapon(attachment.weapon_id), String(attachment.id))
		assert_between(attachment.unlock_level, 1, Armory.catalog.max_level(),
			String(attachment.id))
		assert_ne(attachment.description, "", String(attachment.id))


## De costado, no para arriba: si un attachment solo diera, tenerlo desbloqueado
## seria jugar con ventaja en la tabla.
func test_every_attachment_gives_something_and_costs_something() -> void:
	for attachment: AttachmentData in Armory.catalog.attachments:
		assert_gte(attachment.stat_modifiers.size(), 2,
			"%s solo cambia una cosa: no cobra nada" % attachment.id)
		for modifier: StatModifier in attachment.stat_modifiers:
			assert_true(WEAPON_STATS.has(modifier.stat_key),
				"%s mueve %s, que ningun arma lee" % [attachment.id, modifier.stat_key])


func test_every_weapon_has_one_attachment_per_slot() -> void:
	var shop: ShopCatalog = load(SHOP_CATALOG_PATH)
	for weapon: WeaponData in shop.weapons:
		var slots: Array[int] = []
		for attachment: AttachmentData in Armory.get_attachments(weapon.id):
			assert_false(slots.has(attachment.slot), "%s repite ranura" % weapon.id)
			slots.append(attachment.slot)
		assert_eq(slots.size(), AttachmentData.Slot.size(), String(weapon.id))


func test_the_armory_screen_shows_locks_and_levels() -> void:
	var panel := ArmoryPanel.new()
	add_child_autofree(panel)
	panel.open()
	await wait_process_frames(1)
	var locked: int = 0
	for row: Node in panel._rows.get_children():
		for child: Node in row.get_children():
			var button := child as CheckButton
			if button != null and button.disabled:
				locked += 1
	assert_eq(locked, Armory.catalog.attachments.size(), "sin jugar, todo bloqueado")
	var shop: ShopCatalog = load(SHOP_CATALOG_PATH)
	assert_string_contains(ArmoryPanel.describe_weapon(shop.weapons[0]), "LEVEL 0/")
