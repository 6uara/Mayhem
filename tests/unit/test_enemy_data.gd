extends GutTest
## Guards the authored archetypes: every one of them must be complete, or an
## enemy spawns with no brain, no silhouette or no audio and nothing errors.

const ARCHETYPES: Array[String] = ["rusher", "ranger", "elite", "healer", "summoner",
	"bomber"]


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
	assert_eq(_load("bomber").archetype, EnemyData.Archetype.BOMBER)


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


## Una espoleta incompleta no falla: el Bomber camina hasta vos, hace tic, y no
## pasa nada. Sin escena de explosion no hay estallido; con radio o daño en cero
## el estallido existe y no toca a nadie. Las tres se ven igual desde afuera - un
## enemigo que no hace nada - y ninguna tira un error.
func test_every_fused_archetype_can_actually_explode() -> void:
	for archetype: String in ARCHETYPES:
		var data: EnemyData = _load(archetype)
		if not data.has_fuse:
			continue
		assert_not_null(data.explosion_scene, "%s explosion_scene" % archetype)
		assert_gt(data.fuse_time, 0.0, "%s fuse_time" % archetype)
		assert_gt(data.explosion_radius, 0.0, "%s explosion_radius" % archetype)
		assert_gt(data.explosion_damage, 0.0, "%s explosion_damage" % archetype)
		assert_not_null(data.fuse_sound, "%s fuse_sound" % archetype)
		assert_not_null(data.explosion_sound, "%s explosion_sound" % archetype)


## La cuenta tiene que durar mas de lo que tarda en llegar desde donde se arma.
##
## Es la unica relacion que hace del Bomber una decision y no un golpe: si la
## espoleta termina antes de que el bicho cruce fuse_arm_range, revienta encima
## tuyo siempre y "donde lo hago explotar" no tiene respuesta. Son tres numeros
## en un .tres que se tunean por separado, asi que la relacion se rompe sola.
func test_the_fuse_outlasts_the_walk_from_where_it_arms() -> void:
	for archetype: String in ARCHETYPES:
		var data: EnemyData = _load(archetype)
		if not data.has_fuse:
			continue
		var arm_range: float = data.fuse_arm_range if data.fuse_arm_range > 0.0 \
			else data.attack_range
		var walk_time: float = arm_range / maxf(data.move_speed, 0.1)
		assert_lt(walk_time, data.fuse_time,
			"%s: se arma a %.1fm y camina a %.1f m/s, o sea %.2fs de viaje, pero la espoleta dura %.2fs"
				% [archetype, arm_range, data.move_speed, walk_time, data.fuse_time])
