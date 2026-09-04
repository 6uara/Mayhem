extends GutTest
## The bridge between the arena editor and the game: the player's arena files
## and the state that survives a playtest.


func before_each() -> void:
	for path: String in ArenaSession.list_arenas():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	ArenaSession.new_arena()
	ArenaSession.is_playtesting = false


func after_all() -> void:
	for path: String in ArenaSession.list_arenas():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	ArenaSession.new_arena()


func _fill_playable() -> void:
	var model := PlacementModel.new(ArenaSession.arena, ArenaSession.catalog)
	for x: int in 8:
		for z: int in 8:
			model.place(&"floor_1x1", Vector3i(x, 0, z))
	model.set_player_spawn(Vector3i(0, 0, 0))
	model.add_enemy_spawn(Vector3i(7, 0, 7))


func test_the_catalog_loads() -> void:
	assert_not_null(ArenaSession.catalog, "the editor is unusable without it")
	assert_gt(ArenaSession.catalog.pieces.size(), 9, "the catalog ships 10-15 pieces")


func test_a_new_arena_is_empty_and_unsaved() -> void:
	var arena: ArenaData = ArenaSession.new_arena()
	assert_eq(arena.placements.size(), 0)
	assert_false(arena.has_player_spawn)
	assert_eq(ArenaSession.current_path, "")


func test_saving_names_the_file_after_the_arena() -> void:
	ArenaSession.arena.arena_name = "My First Pit"
	assert_eq(ArenaSession.save(), OK)
	assert_eq(ArenaSession.current_path, "user://arenas/my_first_pit.tres")
	assert_true(FileAccess.file_exists(ArenaSession.current_path))


func test_saved_arenas_come_back_the_same() -> void:
	_fill_playable()
	ArenaSession.arena.arena_name = "Round Trip"
	ArenaSession.save()
	var saved: Dictionary = ArenaSession.arena.to_dict()
	var path: String = ArenaSession.current_path

	ArenaSession.new_arena()
	assert_true(ArenaSession.load_arena(path))
	assert_eq(ArenaSession.arena.to_dict(), saved)


func test_the_arena_list_holds_what_was_saved() -> void:
	assert_eq(ArenaSession.list_arenas().size(), 0, "the folder starts empty")
	ArenaSession.arena.arena_name = "One"
	ArenaSession.save()
	ArenaSession.new_arena()
	ArenaSession.arena.arena_name = "Two"
	ArenaSession.save()
	assert_eq(ArenaSession.list_arenas().size(), 2)


func test_deleting_forgets_the_current_path() -> void:
	ArenaSession.arena.arena_name = "Doomed"
	ArenaSession.save()
	var path: String = ArenaSession.current_path
	assert_eq(ArenaSession.delete_arena(path), OK)
	assert_eq(ArenaSession.current_path, "")
	assert_eq(ArenaSession.list_arenas().size(), 0)


func test_an_unnamed_arena_still_gets_a_filename() -> void:
	ArenaSession.arena.arena_name = "   "
	assert_eq(ArenaSession.path_for_name(ArenaSession.arena.arena_name),
		"user://arenas/arena.tres")


func test_an_empty_arena_is_not_playable() -> void:
	assert_false(ArenaSession.is_playable())
	assert_false(ArenaSession.playtest(), "a broken arena never reaches the loader")
	assert_false(ArenaSession.is_playtesting)


func test_a_finished_arena_is_playable() -> void:
	_fill_playable()
	assert_true(ArenaSession.is_playable(),
		"floor, one player spawn and one reachable enemy spawn is all it takes")


func test_the_grid_can_grow_freely() -> void:
	_fill_playable()
	assert_true(ArenaSession.resize(ArenaData.SIZE_PRESETS["Large  32x8x32"]))
	assert_eq(ArenaSession.arena.grid_size, Vector3i(32, 8, 32))


func test_shrinking_is_refused_while_a_piece_would_be_left_outside() -> void:
	var model := PlacementModel.new(ArenaSession.arena, ArenaSession.catalog)
	model.place(&"floor_1x1", Vector3i(20, 0, 20))
	assert_false(ArenaSession.can_resize(Vector3i(16, 6, 16)))
	assert_false(ArenaSession.resize(Vector3i(16, 6, 16)))
	assert_eq(ArenaSession.arena.grid_size, ArenaData.FIXED_SIZE, "nothing changed")


func test_shrinking_is_allowed_once_the_outliers_are_gone() -> void:
	var model := PlacementModel.new(ArenaSession.arena, ArenaSession.catalog)
	model.place(&"floor_1x1", Vector3i(20, 0, 20))
	model.erase_at(Vector3i(20, 0, 20))
	assert_true(ArenaSession.resize(Vector3i(16, 6, 16)))


## El tamano dejo de ser una eleccion: una arena nueva nace en el unico que hay.
func test_a_new_arena_is_born_at_the_fixed_size() -> void:
	ArenaSession.new_arena()
	assert_eq(ArenaSession.arena.grid_size, ArenaData.FIXED_SIZE)


func test_every_size_preset_is_a_grid_the_editor_can_open() -> void:
	for size: Vector3i in ArenaData.SIZE_PRESETS.values():
		assert_gt(size.x, 0)
		assert_gt(size.y, 0)
		assert_gt(size.z, 0)


func test_saving_a_shipped_arena_writes_the_players_own_copy() -> void:
	assert_true(ArenaSession.load_arena("res://data/arenas/default_arena.tres"),
		"the shipped arena is loadable")
	assert_eq(ArenaSession.save(), OK)
	assert_true(ArenaSession.current_path.begins_with(ArenaSession.USER_DIR),
		"SAVE never writes back into res://")
	assert_eq(ArenaSession.list_arenas().size(), 1)
