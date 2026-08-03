extends GutTest
## Guards the authored archetypes: every one of the five must be complete, or an
## enemy spawns with no brain, no silhouette or no audio and nothing errors.

const ARCHETYPES: Array[String] = ["rusher", "ranger", "elite", "healer", "summoner"]


func _load(name: String) -> EnemyData:
	return load("res://data/enemies/%s.tres" % name)


func test_all_archetypes_load() -> void:
	for name: String in ARCHETYPES:
		assert_not_null(_load(name), name)


func test_every_archetype_has_a_behavior_tree() -> void:
	for name: String in ARCHETYPES:
		assert_not_null(_load(name).behavior_tree, "%s behavior_tree" % name)


func test_every_archetype_is_readable_by_silhouette_and_sound() -> void:
	for name: String in ARCHETYPES:
		var data: EnemyData = _load(name)
		assert_not_null(data.mesh, "%s mesh" % name)
		assert_not_null(data.spawn_sound, "%s spawn_sound" % name)
		assert_not_null(data.windup_sound, "%s windup_sound" % name)
		assert_not_null(data.death_sound, "%s death_sound" % name)


func test_archetype_enum_matches_the_resource() -> void:
	assert_eq(_load("rusher").archetype, EnemyData.Archetype.RUSHER)
	assert_eq(_load("ranger").archetype, EnemyData.Archetype.RANGER)
	assert_eq(_load("elite").archetype, EnemyData.Archetype.ELITE)
	assert_eq(_load("healer").archetype, EnemyData.Archetype.HEALER)
	assert_eq(_load("summoner").archetype, EnemyData.Archetype.SUMMONER)


func test_ranged_archetypes_have_a_projectile() -> void:
	assert_not_null(_load("ranger").projectile_scene, "the ranger must be able to shoot")


func test_summoner_summons_something_that_is_not_itself() -> void:
	var summoner: EnemyData = _load("summoner")
	assert_not_null(summoner.summon_data, "summon_data")
	assert_ne(summoner.summon_data.id, summoner.id, "a summoner must not summon summoners")


func test_every_attack_is_telegraphed() -> void:
	# Telegraphing is mandatory (CLAUDE.md 5.3) and scales with damage.
	for name: String in ARCHETYPES:
		var data: EnemyData = _load(name)
		assert_gt(data.attack_windup, 0.0, "%s attack_windup" % name)


func test_elite_hits_hardest_and_telegraphs_longest() -> void:
	var elite: EnemyData = _load("elite")
	for name: String in ARCHETYPES:
		var data: EnemyData = _load(name)
		assert_true(elite.damage >= data.damage, "elite damage vs %s" % name)
		assert_true(elite.attack_windup >= data.attack_windup, "elite windup vs %s" % name)


func test_rewards_scale_with_threat() -> void:
	assert_gt(_load("elite").reward_currency, _load("rusher").reward_currency)
