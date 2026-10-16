extends GutTest
## Lo que test_stat_modifier.gd no cubre del UpgradeManager: las mejoras
## temporales, sacar una mejora entera y el alcance por arma.
##
## Las temporales existen en el contenido (adrenaline.tres) y no tenian un solo
## test: un vencimiento que no vence es una mejora permanente comprada a precio
## de temporal, y no se ve hasta que alguien mira los numeros.


func _make(id: StringName, category: UpgradeData.Category, stacks: int = 1,
		duration: float = 0.0) -> UpgradeData:
	var modifier := StatModifier.new()
	modifier.stat_key = &"damage"
	modifier.operation = StatModifier.Operation.ADD
	modifier.value = 5.0
	var upgrade := UpgradeData.new()
	upgrade.id = id
	upgrade.category = category
	upgrade.max_stacks = stacks
	upgrade.stat_modifiers = [modifier]
	upgrade.is_temporary = duration > 0.0
	upgrade.duration = duration
	return upgrade


func before_each() -> void:
	UpgradeManager.reset()


func after_each() -> void:
	UpgradeManager.reset()


# ---------------------------------------------------------------- temporales

func test_a_temporary_upgrade_counts_down_and_then_expires() -> void:
	var rush: UpgradeData = _make(&"rush", UpgradeData.Category.MOBILITY, 1, 2.0)
	UpgradeManager.add_upgrade(rush)
	assert_almost_eq(UpgradeManager.get_temporary_remaining(&"rush"), 2.0, 0.001)

	UpgradeManager._process(1.5)
	assert_almost_eq(UpgradeManager.get_temporary_remaining(&"rush"), 0.5, 0.001)
	assert_eq(UpgradeManager.get_stat(&"damage", 10.0), 15.0, "todavia aplica")

	watch_signals(UpgradeManager)
	UpgradeManager._process(0.6)
	assert_false(UpgradeManager.has_upgrade(&"rush"), "vencio")
	assert_eq(UpgradeManager.get_stat(&"damage", 10.0), 10.0, "y ya no suma")
	assert_signal_emitted(UpgradeManager, "upgrades_changed")


## Vence entera: todas sus stacks juntas, porque comparten un solo reloj.
func test_a_stacked_temporary_expires_with_all_its_stacks() -> void:
	var rush: UpgradeData = _make(&"rush", UpgradeData.Category.MOBILITY, 3, 2.0)
	UpgradeManager.add_upgrade(rush)
	UpgradeManager.add_upgrade(rush)
	assert_eq(UpgradeManager.get_stacks(&"rush"), 2)
	UpgradeManager._process(2.5)
	assert_eq(UpgradeManager.get_stacks(&"rush"), 0)


func test_buying_a_temporary_again_refreshes_its_clock() -> void:
	var rush: UpgradeData = _make(&"rush", UpgradeData.Category.MOBILITY, 2, 2.0)
	UpgradeManager.add_upgrade(rush)
	UpgradeManager._process(1.5)
	UpgradeManager.add_upgrade(rush)
	assert_almost_eq(UpgradeManager.get_temporary_remaining(&"rush"), 2.0, 0.001)


func test_a_permanent_upgrade_never_expires() -> void:
	UpgradeManager.add_upgrade(_make(&"armor", UpgradeData.Category.SURVIVABILITY))
	UpgradeManager._process(9999.0)
	assert_true(UpgradeManager.has_upgrade(&"armor"))
	assert_eq(UpgradeManager.get_temporary_remaining(&"armor"), 0.0)


func test_the_owned_entries_report_the_time_left() -> void:
	UpgradeManager.add_upgrade(_make(&"rush", UpgradeData.Category.MOBILITY, 1, 3.0))
	UpgradeManager._process(1.0)
	var entries: Array[Dictionary] = UpgradeManager.get_owned_entries()
	assert_eq(entries.size(), 1)
	assert_almost_eq(float(entries[0]["remaining"]), 2.0, 0.001)


# ---------------------------------------------------------------- remove_upgrade

func test_removing_an_upgrade_takes_every_stack_and_its_clock() -> void:
	var rush: UpgradeData = _make(&"rush", UpgradeData.Category.MOBILITY, 3, 5.0)
	UpgradeManager.add_upgrade(rush)
	UpgradeManager.add_upgrade(rush)
	watch_signals(UpgradeManager)
	UpgradeManager.remove_upgrade(&"rush")
	assert_eq(UpgradeManager.get_stacks(&"rush"), 0)
	assert_eq(UpgradeManager.get_temporary_remaining(&"rush"), 0.0)
	assert_true(UpgradeManager.can_add(rush), "y se puede volver a comprar")
	assert_signal_emitted(UpgradeManager, "upgrades_changed")


func test_removing_something_not_owned_is_silent() -> void:
	watch_signals(UpgradeManager)
	UpgradeManager.remove_upgrade(&"nothing")
	assert_signal_not_emitted(UpgradeManager, "upgrades_changed")


func test_removing_a_weapon_upgrade_only_touches_that_weapon() -> void:
	var mag: UpgradeData = _make(&"mag", UpgradeData.Category.WEAPON)
	UpgradeManager.add_upgrade(mag, &"smg")
	UpgradeManager.add_upgrade(mag, &"rifle")
	UpgradeManager.remove_upgrade(&"mag", &"smg")
	assert_false(UpgradeManager.has_upgrade(&"mag", &"smg"))
	assert_true(UpgradeManager.has_upgrade(&"mag", &"rifle"))


# ---------------------------------------------------------------- alcance

func test_a_weapon_upgrade_without_a_weapon_is_refused() -> void:
	var mag: UpgradeData = _make(&"mag", UpgradeData.Category.WEAPON)
	assert_false(UpgradeManager.add_upgrade(mag))
	assert_push_error("needs a weapon_id")
	assert_eq(UpgradeManager.get_owned().size(), 0)


func test_a_null_upgrade_is_refused() -> void:
	assert_false(UpgradeManager.add_upgrade(null))
	assert_push_error("null data")
	assert_false(UpgradeManager.can_add(null))


## EconomyManager.try_purchase_upgrade documenta que el arma "se ignora" para una
## mejora global. No se ignoraba: la mejora quedaba guardada bajo "id::arma" y
## cada arma abria otro cupo, asi que una mejora de max_stacks 1 se podia
## comprar una vez por arma.
func test_a_global_upgrade_ignores_the_weapon_it_is_bought_with() -> void:
	var armor: UpgradeData = _make(&"armor", UpgradeData.Category.SURVIVABILITY)
	assert_true(UpgradeManager.add_upgrade(armor, &"smg"))
	assert_false(UpgradeManager.can_add(armor, &"rifle"), "el cupo es uno solo")
	assert_false(UpgradeManager.add_upgrade(armor, &"rifle"))
	assert_true(UpgradeManager.has_upgrade(&"armor"), "y se encuentra sin arma")
	assert_eq(UpgradeManager.get_stat(&"damage", 10.0), 15.0)


func test_the_entries_name_the_weapon_only_for_weapon_upgrades() -> void:
	UpgradeManager.add_upgrade(_make(&"mag", UpgradeData.Category.WEAPON), &"smg")
	UpgradeManager.add_upgrade(_make(&"armor", UpgradeData.Category.SURVIVABILITY))
	var by_id: Dictionary = {}
	for entry: Dictionary in UpgradeManager.get_owned_entries():
		by_id[(entry["data"] as UpgradeData).id] = entry
	assert_eq(by_id[&"mag"]["weapon_id"], &"smg")
	assert_eq(by_id[&"armor"]["weapon_id"], &"")


func test_a_zero_max_stacks_still_allows_one() -> void:
	var odd: UpgradeData = _make(&"odd", UpgradeData.Category.MOBILITY, 0)
	assert_true(UpgradeManager.add_upgrade(odd))
	assert_false(UpgradeManager.add_upgrade(odd))


func test_dying_drops_every_upgrade() -> void:
	UpgradeManager.add_upgrade(_make(&"armor", UpgradeData.Category.SURVIVABILITY))
	# Morir tambien deja a GameManager en GAME_OVER; se devuelve como estaba.
	var previous_state: GameManager.State = GameManager.state
	EventBus.player_died.emit()
	GameManager.state = previous_state
	assert_eq(UpgradeManager.get_owned().size(), 0)
