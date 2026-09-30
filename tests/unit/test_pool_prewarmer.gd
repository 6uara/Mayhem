extends GutTest
## The first bullet of a run must not be the one that pays for instantiating the
## bullet scene.

const GAME_SCENE: String = "res://scenes/main/game.tscn"
const PROJECTILE: String = "res://scenes/projectiles/projectile.tscn"


func after_each() -> void:
	ObjectPool.clear()


func test_it_fills_the_pool_before_anything_asks() -> void:
	ObjectPool.clear()
	var scene: PackedScene = load(PROJECTILE)
	var prewarmer := PoolPrewarmer.new()
	prewarmer.scenes = [scene]
	prewarmer.counts = PackedInt32Array([5])
	add_child_autofree(prewarmer)
	assert_eq(ObjectPool.get_free_count(scene), 5)


## Reads the game scene rather than trusting it: a weapon whose bullet scene is not
## in the list is a weapon whose first shot hitches.
func test_the_game_scene_prewarms_every_weapons_projectile() -> void:
	var state: SceneState = (load(GAME_SCENE) as PackedScene).get_state()
	var prewarmed: Array = []
	for node: int in state.get_node_count():
		if state.get_node_name(node) != &"PoolPrewarmer":
			continue
		for prop: int in state.get_node_property_count(node):
			if state.get_node_property_name(node, prop) == &"scenes":
				prewarmed = state.get_node_property_value(node, prop)
	assert_false(prewarmed.is_empty(), "the game scene has a PoolPrewarmer with scenes")
	for file: String in DirAccess.get_files_at("res://data/weapons"):
		var path: String = "res://data/weapons/" + file.trim_suffix(".remap")
		if not path.ends_with(".tres"):
			continue
		var weapon := load(path) as WeaponData
		if weapon == null or weapon.projectile_scene == null:
			continue
		assert_true(prewarmed.has(weapon.projectile_scene),
			"%s's projectile is prewarmed" % weapon.id)
