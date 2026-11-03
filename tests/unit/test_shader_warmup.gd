extends GutTest
## El precalentado de shaders detras de la transicion de carga. Lo que se puede
## probar sin render: que arma copias de todo, que las copias no hacen nada, y que
## la lista que sale con el juego carga entera.

const LIST_PATH: String = "res://data/render/shader_warmup.tres"


func _list() -> ShaderWarmupList:
	return load(LIST_PATH) as ShaderWarmupList


func test_the_shipped_list_loads_every_scene() -> void:
	var list: ShaderWarmupList = _list()
	assert_not_null(list)
	assert_false(list.scenes.is_empty())
	for scene: PackedScene in list.scenes:
		assert_not_null(scene, "una escena de la lista no carga")


func test_the_copies_have_no_scripts_left() -> void:
	var warmup := ShaderWarmup.new()
	warmup.list = _list()
	add_child_autofree(warmup)
	var copies: Array[Node3D] = warmup.build_copies()
	assert_gt(copies.size(), warmup.list.scenes.size(), "tambien los modelos de enemigos")
	for copy: Node3D in copies:
		assert_eq(_scripts_in(copy), 0, "%s conserva un script" % copy.name)
		copy.free()


## Una explosion de la lista no puede lastimar ni sonar: entra al arbol sin su
## script, asi que su _ready() de juego no corre.
func test_a_copy_in_the_tree_does_not_emit_gameplay_signals() -> void:
	watch_signals(EventBus)
	var warmup := ShaderWarmup.new()
	warmup.list = _list()
	add_child_autofree(warmup)
	for copy: Node3D in warmup.build_copies():
		warmup.add_child(copy)
	await wait_physics_frames(2)
	assert_signal_not_emitted(EventBus, "player_damaged")
	assert_signal_not_emitted(EventBus, "player_hit")


func test_without_a_camera_it_draws_nothing() -> void:
	var warmup := ShaderWarmup.new()
	warmup.list = _list()
	add_child_autofree(warmup)
	if get_viewport().get_camera_3d() == null:
		assert_eq(await warmup.run(), 0)
	else:
		pass_test("la suite tiene una camara")


func _scripts_in(node: Node) -> int:
	var count: int = 1 if node.get_script() != null else 0
	for child: Node in node.get_children():
		count += _scripts_in(child)
	return count
