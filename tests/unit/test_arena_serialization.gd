extends GutTest
## Round-tripping arenas, and reading a file written by an older format version.


func _arena() -> ArenaData:
	var arena := ArenaData.new()
	arena.arena_name = "Test Arena"
	arena.grid_size = Vector3i(24, 8, 24)
	arena.placements = [
		PlacementEntry.make(&"floor", Vector3i(1, 0, 2), 0),
		PlacementEntry.make(&"ramp", Vector3i(3, 0, 2), 3),
	]
	arena.player_spawn = Vector3i(1, 0, 2)
	arena.has_player_spawn = true
	arena.enemy_spawns = [EnemySpawnEntry.make(Vector3i(3, 0, 2), &"rusher")]
	arena.author = "gut"
	return arena


func test_dict_round_trip_preserves_the_arena() -> void:
	var original: ArenaData = _arena()
	var restored: ArenaData = ArenaData.from_dict(original.to_dict())
	assert_eq(restored.arena_name, original.arena_name)
	assert_eq(restored.grid_size, original.grid_size)
	assert_eq(restored.player_spawn, original.player_spawn)
	assert_true(restored.has_player_spawn)
	assert_eq(restored.placements.size(), 2)
	assert_eq(restored.placements[1].piece_id, &"ramp")
	assert_eq(restored.placements[1].rotation, 3)
	assert_eq(restored.enemy_spawns[0].archetype_id, &"rusher")


func test_json_round_trip_preserves_the_arena() -> void:
	var restored: ArenaData = ArenaData.from_json(_arena().to_json())
	assert_not_null(restored)
	assert_eq(restored.to_dict(), _arena().to_dict())


func test_a_version_1_file_still_loads() -> void:
	var legacy: Dictionary = {
		"format_version": 1,
		"arena_name": "Legacy",
		"grid_size": [16, 6, 16],
		"placements": [{"piece_id": "floor", "cell": [2, 0, 2], "rotation": 1}],
		"player_spawn": [2, 0, 2],
		"enemy_spawns": [{"cell": [4, 0, 4], "archetype_id": ""}],
	}
	var arena: ArenaData = ArenaData.from_dict(legacy)
	assert_eq(arena.format_version, ArenaData.CURRENT_FORMAT_VERSION)
	assert_eq(arena.arena_name, "Legacy")
	assert_true(arena.has_player_spawn, "v1 marked the spawn by having one at all")
	assert_eq(arena.placements[0].rotation, 1)
	assert_eq(arena.author, "", "fields added after v1 come back empty, not missing")


func test_a_version_2_file_gets_the_default_venue() -> void:
	var legacy: Dictionary = {
		"format_version": 2,
		"arena_name": "Themeless",
		"grid_size": [16, 6, 16],
		"has_player_spawn": true,
		"player_spawn": [1, 0, 1],
		"placements": [],
		"enemy_spawns": [],
	}
	var arena: ArenaData = ArenaData.from_dict(legacy)
	assert_eq(arena.format_version, ArenaData.CURRENT_FORMAT_VERSION)
	assert_eq(arena.theme_id, &"default", "arenas made before themes get one")


func test_the_theme_survives_a_round_trip() -> void:
	var arena: ArenaData = _arena()
	arena.theme_id = &"stadium"
	assert_eq(ArenaData.from_json(arena.to_json()).theme_id, &"stadium")
