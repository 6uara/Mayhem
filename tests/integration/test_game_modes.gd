extends GutTest
## Los dos modos de juego y la tabla por arena.
##
## ARSENAL arranca con la pistola y la tienda vende armas, todas con precio. ONE
## GUN arranca con el arma elegida y la tienda no vende ninguna. Y cada arena
## tiene su propia tabla: una arena hecha a medida no compite con la del juego.

const CATALOG_PATH: String = "res://data/economy/shop_catalog.tres"

var _saved_file: Variant = null
var _saved_profiles: Array[String] = []


func before_each() -> void:
	# La tabla es un archivo real del jugador: se guarda tal cual y se devuelve.
	_saved_file = null
	if FileAccess.file_exists(SaveManager.SAVE_PATH):
		_saved_file = FileAccess.get_file_as_string(SaveManager.SAVE_PATH)
	_saved_profiles = SaveManager.get_profiles()
	SaveManager.clear_leaderboard()


func after_each() -> void:
	GameManager.set_run_mode(GameManager.Mode.ARSENAL)
	if _saved_file == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.SAVE_PATH))
	else:
		var file: FileAccess = FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
		file.store_string(String(_saved_file))
		file.close()
	SaveManager.load_leaderboard()
	SaveManager.forget_profiles()
	for index: int in range(_saved_profiles.size() - 1, -1, -1):
		SaveManager.remember_profile(_saved_profiles[index])


func _shop() -> Shop:
	var shop := Shop.new()
	shop.catalog = load(CATALOG_PATH)
	add_child_autofree(shop)
	return shop


func _weapon_offers(shop: Shop) -> int:
	var count: int = 0
	for offer: Dictionary in shop._build_pool():
		if int(offer["kind"]) == Shop.Kind.WEAPON:
			count += 1
	return count


# ------------------------------------------------------------------ modos

## "Todas deberian tener un precio": el rifle salia gratis desde que dejo de ser
## el arma inicial, y la pistola volvia a ofrecerse gratis despues de cambiarla.
func test_every_weapon_in_the_shop_has_a_price() -> void:
	var catalog: ShopCatalog = load(CATALOG_PATH)
	for weapon: WeaponData in catalog.weapons:
		assert_gt(catalog.get_weapon_price(weapon.id), 0, "%s tiene precio" % weapon.id)


func test_arsenal_sells_weapons() -> void:
	GameManager.set_run_mode(GameManager.Mode.ARSENAL)
	assert_gt(_weapon_offers(_shop()), 0)
	assert_eq(GameManager.get_starting_weapon_id(), &"", "arranca con la de siempre")


func test_one_gun_never_offers_a_weapon() -> void:
	GameManager.set_run_mode(GameManager.Mode.SINGLE_WEAPON, &"shotgun")
	assert_eq(_weapon_offers(_shop()), 0)
	assert_eq(GameManager.get_starting_weapon_id(), &"shotgun")


func test_one_gun_starts_the_player_with_the_chosen_weapon() -> void:
	GameManager.set_run_mode(GameManager.Mode.SINGLE_WEAPON, &"smg")
	var player: Node = add_child_autofree(
		(load("res://scenes/player/player.tscn") as PackedScene).instantiate())
	await wait_physics_frames(2)
	var holder: WeaponHolder = (player as Player).weapon_holder
	assert_eq(holder.current.data.id, &"smg")


func test_going_back_to_arsenal_forgets_the_weapon() -> void:
	GameManager.set_run_mode(GameManager.Mode.SINGLE_WEAPON, &"rifle_ak")
	GameManager.set_run_mode(GameManager.Mode.ARSENAL, &"rifle_ak")
	assert_eq(GameManager.run_weapon_id, &"")


func test_the_mode_screen_reports_what_was_picked() -> void:
	var select := ModeSelect.new()
	add_child_autofree(select)
	await wait_frames(1)
	select.open()
	select.choose(GameManager.Mode.SINGLE_WEAPON, &"pistol")
	watch_signals(select)
	select.confirm()
	assert_signal_emitted_with_parameters(select, "mode_chosen",
		[GameManager.Mode.SINGLE_WEAPON, &"pistol"])


# ------------------------------------------------------------------ tabla por arena

func test_each_arena_keeps_its_own_table() -> void:
	SaveManager.submit_score(900, 100.0, 3, "TESTER", [], "user://arenas/a.tres", "A")
	SaveManager.submit_score(500, 100.0, 2, "TESTER", [], "")
	assert_eq(SaveManager.get_entries_for("user://arenas/a.tres").size(), 1)
	assert_eq(SaveManager.get_entries_for(SaveManager.DEFAULT_ARENA_ID).size(), 1)
	assert_eq(SaveManager.get_best_score(SaveManager.DEFAULT_ARENA_ID), 500,
		"el 900 de otra arena no es el mejor de esta")


## Llenar una arena no le saca lugar a otra.
func test_the_cap_is_per_arena() -> void:
	for i: int in SaveManager.MAX_ENTRIES + 3:
		SaveManager.submit_score(1000 + i, 10.0, 1, "TESTER", [], "user://arenas/a.tres", "A")
	SaveManager.submit_score(1, 10.0, 1, "TESTER", [], "")
	assert_eq(SaveManager.get_entries_for("user://arenas/a.tres").size(), SaveManager.MAX_ENTRIES)
	assert_eq(SaveManager.get_entries_for("").size(), 1)


## Las filas de antes de la tabla por arena son de la arena por defecto.
func test_rows_saved_before_arenas_belong_to_the_default_arena() -> void:
	var file: FileAccess = FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify([{"name": "OLD", "score": 42, "time": 1.0, "waves": 1}]))
	file.close()
	SaveManager.load_leaderboard()
	var rows: Array[Dictionary] = SaveManager.get_entries_for(SaveManager.DEFAULT_ARENA_ID)
	assert_eq(rows.size(), 1)
	assert_eq(int(rows[0]["mode"]), GameManager.Mode.ARSENAL)


func test_a_row_remembers_its_mode() -> void:
	SaveManager.submit_score(10, 1.0, 1, "TESTER", [], "", "",
		GameManager.Mode.SINGLE_WEAPON)
	assert_eq(int(SaveManager.get_entries()[0]["mode"]), GameManager.Mode.SINGLE_WEAPON)
