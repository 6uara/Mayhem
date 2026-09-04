extends GutTest
## The Play screen's list, and the choice it hands to the next run.


func before_each() -> void:
	for path: String in ArenaSession.list_arenas():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	ArenaSession.set_run_arena("")
	ArenaSession.new_arena()


func after_all() -> void:
	for path: String in ArenaSession.list_arenas():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	ArenaSession.set_run_arena("")


func test_the_shipped_arenas_are_playable_without_building_anything() -> void:
	var entries: Array[Dictionary] = ArenaSession.list_playable()
	assert_gt(entries.size(), 0, "the game ships arenas to play")
	for entry: Dictionary in entries:
		assert_true(bool(entry["shipped"]), "nothing of the player's exists yet")


func test_entries_carry_the_name_the_arena_calls_itself() -> void:
	for entry: Dictionary in ArenaSession.list_playable():
		if entry["path"] == "res://data/arenas/default_arena.tres":
			assert_eq(entry["name"], "The Pit", "not the filename")
			assert_gt(entry["pieces"], 0)
			return
	fail_test("the default arena is missing from the list")


func test_a_players_arena_joins_the_list_marked_as_theirs() -> void:
	var before: int = ArenaSession.list_playable().size()
	ArenaSession.arena.arena_name = "Mine"
	ArenaSession.save()
	var entries: Array[Dictionary] = ArenaSession.list_playable()
	assert_eq(entries.size(), before + 1)
	assert_false(bool(entries[entries.size() - 1]["shipped"]))


func test_choosing_an_arena_is_what_the_next_run_gets() -> void:
	assert_null(ArenaSession.get_run_arena(), "no choice means the scene's default")
	ArenaSession.set_run_arena("res://data/arenas/default_arena.tres")
	var chosen: ArenaData = ArenaSession.get_run_arena()
	assert_not_null(chosen)
	assert_eq(chosen.arena_name, "The Pit")


func test_deleting_the_chosen_arena_forgets_the_choice() -> void:
	ArenaSession.arena.arena_name = "Doomed"
	ArenaSession.save()
	ArenaSession.set_run_arena(ArenaSession.current_path)
	ArenaSession.delete_arena(ArenaSession.current_path)
	assert_eq(ArenaSession.run_arena_path, "", "a run must not point at a deleted file")
	assert_null(ArenaSession.get_run_arena())
