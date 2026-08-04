extends GutTest
## The authored 10-wave session. These catch a broken .tres before a playtest does.

const WAVE_COUNT: int = 10


func _load(index: int) -> WaveData:
	return load("res://data/waves/wave_%02d.tres" % index)


func test_all_ten_waves_load() -> void:
	for i: int in range(1, WAVE_COUNT + 1):
		assert_not_null(_load(i), "wave %d" % i)


func test_every_wave_spawns_something() -> void:
	for i: int in range(1, WAVE_COUNT + 1):
		assert_gt(_load(i).get_total_enemy_count(), 0, "wave %d" % i)


func test_every_spawn_group_is_complete() -> void:
	for i: int in range(1, WAVE_COUNT + 1):
		for group: SpawnGroup in _load(i).spawn_groups:
			assert_not_null(group, "wave %d has a null group" % i)
			assert_not_null(group.enemy_data, "wave %d group enemy_data" % i)
			assert_gt(group.count, 0, "wave %d group count" % i)
			assert_false(group.spawn_door_ids.is_empty(), "wave %d group doors" % i)


func test_wave_index_matches_the_filename() -> void:
	for i: int in range(1, WAVE_COUNT + 1):
		assert_eq(_load(i).wave_index, i - 1, "wave %d index" % i)


func test_elite_waves_are_every_fifth() -> void:
	# CLAUDE.md 5.5: 10 waves, elite wave every 5th.
	for i: int in range(1, WAVE_COUNT + 1):
		assert_eq(_load(i).is_elite_wave, i % 5 == 0, "wave %d elite flag" % i)


func test_difficulty_curve_never_goes_backwards() -> void:
	var previous: int = 0
	for i: int in range(1, WAVE_COUNT + 1):
		# Wave 5 trades bodies for an elite, so only compare within each stretch.
		if i == 5 or i == 10:
			continue
		var count: int = _load(i).get_total_enemy_count()
		assert_true(count >= previous, "wave %d is smaller than wave %d" % [i, i - 1])
		previous = count


## The enemy pool has to cover the biggest authored wave, not the first one.
##
## Falling short does not fail anything - the shortfall is just instantiated live,
## which means the one wave that hitches is by construction the largest fight in the
## run. Raising a wave's counts without raising the pool is an easy thing to do and
## an invisible thing to have done, so the two are pinned together here.
func test_the_enemy_pool_covers_the_largest_wave() -> void:
	var largest: int = 0
	for i: int in range(1, WAVE_COUNT + 1):
		largest = maxi(largest, _load(i).get_total_enemy_count())

	var prewarm: int = _authored_prewarm()
	assert_gt(prewarm, 0, "found the spawner's prewarm_count in game.tscn")
	assert_true(prewarm >= largest,
		"pool prewarms %d but wave content peaks at %d" % [prewarm, largest])


## Read from the packed scene rather than instantiated - this needs one exported
## number, not a running match.
func _authored_prewarm() -> int:
	var state: SceneState = load("res://scenes/main/game.tscn").get_state()
	for node: int in state.get_node_count():
		if state.get_node_name(node) != "EnemySpawner":
			continue
		for property: int in state.get_node_property_count(node):
			if state.get_node_property_name(node, property) == &"prewarm_count":
				return int(state.get_node_property_value(node, property))
	return -1


func test_every_wave_has_a_par_time() -> void:
	for i: int in range(1, WAVE_COUNT + 1):
		assert_gt(_load(i).par_time, 0.0, "wave %d par_time" % i)


## Par time rises across normal waves. Elite waves are excluded because they are
## deliberately slower - an elite is a damage sponge, so wave 5 gets more time than
## the normal wave 6 that follows it.
func test_par_times_rise_across_normal_waves() -> void:
	var previous: float = 0.0
	for i: int in range(1, WAVE_COUNT + 1):
		if _load(i).is_elite_wave:
			continue
		var par: float = _load(i).par_time
		assert_true(par >= previous, "wave %d par_time went backwards" % i)
		previous = par


func test_elite_waves_allow_more_time_than_the_wave_before() -> void:
	for i: int in range(2, WAVE_COUNT + 1):
		if not _load(i).is_elite_wave:
			continue
		assert_gt(_load(i).par_time, _load(i - 1).par_time, "wave %d par_time" % i)
