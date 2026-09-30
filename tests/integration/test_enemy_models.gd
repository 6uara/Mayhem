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


## La caja de todas las mallas del modelo en el espacio del cuerpo del enemigo.
func _body_space_bounds(enemy: Enemy) -> AABB:
	var out := AABB()
	var found: bool = false
	var to_body: Transform3D = enemy.global_transform.affine_inverse()
	for mesh_node: MeshInstance3D in enemy._model_meshes:
		if mesh_node.mesh == null:
			continue
		var box: AABB = to_body * mesh_node.global_transform * mesh_node.mesh.get_aabb()
		out = box if not found else out.merge(box)
		found = true
	return out


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
##
## Se mide en el espacio del cuerpo, ya orientado: el Healer llega acostado y se
## para con `model_pitch_degrees`, asi que su alto de verdad es otro eje de la malla.
func test_fit_height_sizes_the_model_from_its_mesh() -> void:
	var enemy: Enemy = await _spawn("healer")
	assert_gt(enemy.data.model_fit_height, 0.0, "precondition: el healer se ajusta por altura")
	var bounds: AABB = _body_space_bounds(enemy)
	assert_gt(bounds.size.y, 0.0, "la malla se pudo medir")
	assert_almost_eq(bounds.size.y, enemy.data.model_fit_height, 0.15,
		"el modelo mide lo que pide el arquetipo (%0.2f)" % bounds.size.y)
	assert_gt(bounds.size.y, maxf(bounds.size.x, bounds.size.z),
		"y esta parado: el alto es su eje mas largo")


## El Healer trae su propio halo en el modelo; el anillo generado no se dibuja
## encima, pero el arquetipo sigue contando como uno con halo.
func test_the_healer_shows_only_the_models_halo() -> void:
	var enemy: Enemy = await _spawn("healer")
	assert_true(enemy.data.has_halo, "el arquetipo sigue teniendo halo")
	assert_false(enemy.halo.visible, "pero lo dibuja el modelo, no el anillo generado")


## El Bomber flota: su modelo no toca el piso en ningun punto del bob, pero su
## cuerpo sigue en el piso, que es lo que camina el navmesh.
func test_the_bomber_floats_above_the_floor() -> void:
	# Con piso: sin el, el cuerpo cae fuera del mundo y muere en medio del test.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 1.0, 20.0)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	add_child_autofree(floor_body)
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
