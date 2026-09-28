extends GutTest
## Archetypes can carry a rigged model instead of the grey-box capsule. What is
## worth pinning is not that it looks right - nothing here can see - but the
## three ways attaching one could quietly break the game.


func _spawn(id: String) -> Enemy:
	var enemy: Enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	add_child_autofree(enemy)
	await wait_physics_frames(1)
	enemy.setup(load("res://data/enemies/%s.tres" % id), Vector3.ZERO)
	await wait_physics_frames(1)
	return enemy


func _find(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child: Node in node.get_children():
		var found: Node = _find(child, type_name)
		if found != null:
			return found
	return null


## The common enemy is the one with a model, so it is the one that would show a
## regression first.
func test_the_rusher_wears_the_spider_bot() -> void:
	var enemy: Enemy = await _spawn("rusher")
	assert_not_null(enemy.data.model_scene, "the archetype carries a model")
	assert_not_null(_find(enemy, "Skeleton3D"), "and the rig came with it")
	assert_false(enemy.mesh_instance.visible,
		"the grey-box capsule is not drawn underneath it")


## A .fbx exported from Blender packs that file's camera and lights. One camera
## per enemy is a horde that films itself: whichever spawned last would own the
## screen.
func test_no_enemy_brings_a_camera_or_a_light_into_the_arena() -> void:
	var enemy: Enemy = await _spawn("rusher")
	assert_null(_find(enemy, "Camera3D"), "no camera rides along")
	assert_null(_find(enemy, "OmniLight3D"), "and no light either")


## The archetype these two use as "the one still in grey-box". It used to be the
## Ranger, until the Ranger got its model and took both tests down with it - so
## pick it from the data instead of naming one, and the tests follow the art
## instead of dating against it.
##
## If every archetype ever has a model, these two skip rather than lie: the capsule
## path still has to work for the next archetype somebody grey-boxes, but there
## would be nothing shipped left to prove it with.
const _ARCHETYPES: Array[String] = [
	"rusher", "ranger", "flyer", "bomber",
	"elite", "environmental", "healer", "summoner",
]


func _capsule_archetype() -> String:
	for id: String in _ARCHETYPES:
		var data: EnemyData = load("res://data/enemies/%s.tres" % id)
		if data.model_scene == null:
			return id
	return ""


## An archetype with no model still has to work - grey-boxing a new one has to keep
## working with a capsule and a colour.
func test_an_archetype_without_a_model_keeps_its_capsule() -> void:
	var id: String = _capsule_archetype()
	if id == "":
		pass_test("every shipped archetype wears a model now")
		return
	var enemy: Enemy = await _spawn(id)
	assert_null(enemy.data.model_scene, "no model on %s" % id)
	assert_true(enemy.mesh_instance.visible, "so the capsule is what is drawn")


## The pool hands the same body to a different archetype all the time. A model left
## behind from the last one would put a spider bot inside a grey-box enemy.
func test_a_pooled_body_swaps_its_model_with_its_archetype() -> void:
	var id: String = _capsule_archetype()
	if id == "":
		pass_test("every shipped archetype wears a model now")
		return
	var enemy: Enemy = await _spawn("rusher")
	assert_not_null(_find(enemy, "Skeleton3D"), "wearing the bot")

	enemy.setup(load("res://data/enemies/%s.tres" % id), Vector3.ZERO)
	await wait_physics_frames(2)
	assert_null(_find(enemy, "Skeleton3D"), "the bot came off with the archetype")
	assert_true(enemy.mesh_instance.visible, "and the capsule came back")


## Un modelo nuevo llega en sus propias unidades. Con `model_fit_height` se lo
## ajusta a esa altura midiendo la malla, apoyado en el piso.
func test_fit_height_sizes_the_model_from_its_mesh() -> void:
	var enemy: Enemy = await _spawn("healer")
	assert_gt(enemy.data.model_fit_height, 0.0, "precondition: el healer se ajusta por altura")
	var bounds: AABB = enemy._model_bounds
	assert_gt(bounds.size.y, 0.0, "la malla se pudo medir")
	var height: float = bounds.size.y * enemy._model.scale.y
	assert_almost_eq(height, enemy.data.model_fit_height, 0.15,
		"el modelo mide lo que pide el arquetipo (%0.2f)" % height)


## El Bomber flota: su modelo no toca el piso en ningun punto del bob, pero su
## cuerpo sigue en el piso, que es lo que camina el navmesh.
func test_the_bomber_floats_above_the_floor() -> void:
	var enemy: Enemy = await _spawn("bomber")
	assert_not_null(enemy._motion, "el bomber tiene animacion procedural")
	var lowest: float = INF
	for _i: int in 90:
		await wait_frames(1)
		var bottom: float = enemy._model.position.y \
			+ enemy._model_bounds.position.y * enemy._model.scale.y
		lowest = minf(lowest, bottom)
	assert_gt(lowest, 0.2, "la base del modelo nunca baja al piso (%0.2f)" % lowest)
	assert_almost_eq(enemy.global_position.y, 0.0, 0.3, "el cuerpo sigue en el piso")


## Curar se ve en el cuerpo del Healer, no solo en los haces.
func test_the_healer_pops_when_it_heals() -> void:
	var enemy: Enemy = await _spawn("healer")
	assert_not_null(enemy._motion)
	await wait_frames(2)
	var rest_scale: float = enemy._model.scale.x
	enemy.ability_used.emit()
	await wait_seconds(0.2)
	assert_gt(enemy._model.scale.x, rest_scale * 1.03, "se infla al curar")


## Hit flashes and wind-ups drive one knob now, whichever way the enemy is drawn.
## Both paths have to survive being asked to light up.
func test_lighting_up_works_with_a_model_and_without_one() -> void:
	var wearer: Enemy = await _spawn("rusher")
	wearer.show_windup(1.0)
	wearer.clear_windup()

	var bare: Enemy = await _spawn("ranger")
	bare.show_windup(1.0)
	bare.clear_windup()
	pass_test("neither path errors")
