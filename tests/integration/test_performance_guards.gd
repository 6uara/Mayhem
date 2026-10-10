extends GutTest
## Lo que se hizo por performance y no se tiene que deshacer sin querer.
##
## Cada uno de estos salio de medir en una GPU integrada (Radeon 680M) con
## `tools/profile_elite_wave.gd` y `tools/profile_scene_cost.gd`. Ninguno cambia
## lo que el jugador ve; todos son faciles de romper con un cambio inocente.

var _parent: Node3D


func before_each() -> void:
	_parent = Node3D.new()
	add_child_autofree(_parent)


func _arena() -> ArenaRuntime:
	return ArenaLoader.load_arena(ArenaIO.load_arena("res://data/arenas/default_arena.tres"),
		_parent, ArenaSession.catalog)


## Las ~1450 cajas de la arena se dibujan en un punado de MultiMesh, no una por
## una: eran mas de 3000 draw calls en un frame sin enemigos.
func test_the_arena_draws_its_greybox_in_batches() -> void:
	var runtime: ArenaRuntime = _arena()
	var batched: Node = runtime.get_node_or_null(ArenaGeometryBatcher.ROOT_NAME)
	assert_not_null(batched)
	var batches: int = batched.get_child_count()
	assert_gt(batches, 0)
	assert_lt(batches, 40, "pocas mallas distintas, no una por pieza")
	for child: Node in runtime.geometry_root.get_children():
		if not child.has_meta(PieceMeshBuilder.GREYBOX_META):
			continue
		for grandchild: Node in child.get_children():
			assert_false(grandchild is MeshInstance3D and not grandchild.is_queued_for_deletion(),
				"%s todavia dibuja por su cuenta" % child.name)


## Juntar lo que se dibuja no puede sacar lo que se choca: el navmesh se bakea de
## los colliders y el jugador camina sobre ellos.
func test_batching_keeps_every_collider() -> void:
	var runtime: ArenaRuntime = _arena()
	var shapes: int = 0
	for child: Node in runtime.geometry_root.get_children():
		for grandchild: Node in child.get_children():
			if grandchild is CollisionShape3D:
				shapes += 1
	assert_gt(shapes, 1000)


func test_greybox_pieces_share_meshes_and_materials() -> void:
	var catalog: PieceCatalog = ArenaSession.catalog
	var piece: PieceDefinition = catalog.get_piece(&"floor_3x3")
	var a: Node3D = autofree(PieceMeshBuilder.build(piece, catalog, false, false))
	var b: Node3D = autofree(PieceMeshBuilder.build(piece, catalog, false, false))
	var mesh_a := a.get_child(0) as MeshInstance3D
	var mesh_b := b.get_child(0) as MeshInstance3D
	assert_same(mesh_a.mesh, mesh_b.mesh)
	assert_same(mesh_a.material_override, mesh_b.material_override)


## La IA decide a ritmo espaciado, y las hojas cuentan el tiempo real que paso:
## un telegrafo dura lo mismo decida cada uno o cada cuatro frames.
func test_ai_timers_count_real_time_at_any_tick_rate() -> void:
	var enemy := (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate() as Enemy
	add_child_autofree(enemy)
	enemy.setup(load("res://data/enemies/rusher.tres"), Vector3.ZERO)
	await wait_physics_frames(1)
	var tree := enemy._behavior_tree as BeehaveTree
	assert_not_null(tree)
	tree.tick_rate = 3
	assert_almost_eq(enemy.get_ai_delta(), enemy.get_physics_process_delta_time() * 3.0, 0.0001)
	ObjectPool.release(enemy)


## Lo que un giro le pide al cuerpo se reparte entre frames, no se da de golpe.
func test_a_spaced_turn_is_spread_over_frames() -> void:
	var enemy := (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate() as Enemy
	add_child_autofree(enemy)
	enemy.face_target(0.05, 8.0)
	assert_almost_eq(enemy._face_hold, 0.05 - enemy.get_physics_process_delta_time(), 0.0001)


func test_the_bowl_and_the_crowd_cast_no_shadow() -> void:
	var crowd := CrowdStands.new()
	add_child_autofree(crowd)
	await wait_frames(1)
	if crowd.multimesh != null:
		assert_eq(crowd.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	else:
		pass_test("sin asientos no hay multimesh que medir")


func test_an_integrated_gpu_starts_lighter() -> void:
	var integrated: Dictionary = SettingsManager.effective_defaults(
		RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU)
	var discrete: Dictionary = SettingsManager.effective_defaults(
		RenderingDevice.DEVICE_TYPE_DISCRETE_GPU)
	assert_lt(int(integrated["video/render_scale"]), int(discrete["video/render_scale"]))
	assert_lt(int(integrated["video/shadow_quality"]), int(discrete["video/shadow_quality"]))
	assert_eq(int(discrete["video/render_scale"]), 100, "una GPU dedicada arranca como siempre")


func test_the_sun_draws_two_short_cascades() -> void:
	var runtime: ArenaRuntime = _arena()
	var sun := runtime.get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		pass_test("este tema no trae sol")
		return
	assert_eq(sun.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
	assert_lte(sun.directional_shadow_max_distance, ArenaRuntime.SUN_SHADOW_DISTANCE)
