extends GutTest
## El pool de nodos de alta rotacion. Lo usan enemigos, proyectiles, numeros de
## daño e impactos, y no tenia tests propios: se probaba de rebote.
##
## Cada test usa su propia PackedScene para que los conteos no se mezclen con lo
## que el juego ya tiene en el pool.


class Probe:
	extends Node3D
	var acquired: int = 0
	var released: int = 0

	func _on_acquired() -> void:
		acquired += 1

	func _on_released() -> void:
		released += 1


var _scene: PackedScene


func before_each() -> void:
	var probe := Probe.new()
	_scene = PackedScene.new()
	_scene.pack(probe)
	probe.free()


func after_each() -> void:
	# Solo lo de esta escena: `clear()` entero se llevaria el pool del juego.
	for instance: Node in ObjectPool._in_use.keys().duplicate():
		if is_instance_valid(instance) and ObjectPool._in_use[instance] == _scene:
			ObjectPool.release(instance)
	for instance: Variant in ObjectPool._free.get(_scene, []):
		if is_instance_valid(instance):
			(instance as Node).free()
	ObjectPool._free.erase(_scene)
	var container: Variant = ObjectPool._containers.get(_scene)
	if is_instance_valid(container):
		(container as Node).free()
	ObjectPool._containers.erase(_scene)


func test_prewarm_fills_the_free_list_with_dormant_nodes() -> void:
	ObjectPool.prewarm(_scene, 3)
	assert_eq(ObjectPool.get_free_count(_scene), 3)
	for instance: Variant in ObjectPool._free[_scene]:
		var node := instance as Node3D
		assert_eq(node.process_mode, Node.PROCESS_MODE_DISABLED)
		assert_false(node.visible)
		assert_true(node.is_in_group(ObjectPool.RELEASED_GROUP))


func test_acquire_reuses_a_prewarmed_node_instead_of_instancing() -> void:
	ObjectPool.prewarm(_scene, 1)
	var warmed: Node = ObjectPool._free[_scene][0]
	var got: Node = ObjectPool.acquire(_scene)
	assert_same(got, warmed)
	assert_eq(ObjectPool.get_free_count(_scene), 0)


func test_acquire_wakes_the_node_up() -> void:
	var got := ObjectPool.acquire(_scene) as Probe
	assert_true(got.is_inside_tree())
	assert_true(got.visible)
	assert_eq(got.process_mode, Node.PROCESS_MODE_PAUSABLE,
		"pausable, aunque el pool sea PROCESS_MODE_ALWAYS")
	assert_false(got.is_in_group(ObjectPool.RELEASED_GROUP))
	assert_eq(got.acquired, 1)


func test_release_puts_the_node_back_to_sleep() -> void:
	var got := ObjectPool.acquire(_scene) as Probe
	ObjectPool.release(got)
	assert_eq(got.released, 1)
	assert_eq(got.process_mode, Node.PROCESS_MODE_DISABLED)
	assert_false(got.visible)
	assert_lt(got.global_position.y, -1000.0, "fuera de la vista y de toda colision")
	assert_eq(ObjectPool.get_free_count(_scene), 1)


func test_releasing_twice_does_not_pool_the_node_twice() -> void:
	var got: Node = ObjectPool.acquire(_scene)
	ObjectPool.release(got)
	ObjectPool.release(got)
	assert_eq(ObjectPool.get_free_count(_scene), 1)
	assert_eq((got as Probe).released, 1)


func test_releasing_a_node_the_pool_never_gave_out_is_ignored() -> void:
	var stranger := Node.new()
	add_child_autofree(stranger)
	var before: int = ObjectPool.get_active_count()
	ObjectPool.release(stranger)
	ObjectPool.release(null)
	assert_eq(ObjectPool.get_active_count(), before)


func test_a_freed_node_in_the_free_list_is_skipped() -> void:
	ObjectPool.prewarm(_scene, 2)
	(ObjectPool._free[_scene][1] as Node).free()
	var got: Node = ObjectPool.acquire(_scene)
	assert_true(is_instance_valid(got))
	assert_true(ObjectPool._in_use.has(got))


## Un nodo prestado que alguien libera con queue_free() en vez de devolverlo. El
## pool lo seguia contando como activo para siempre, y release_all() lo recorria
## con una variable tipada - asignar un objeto liberado a un `Node` es un error.
func test_a_lent_node_freed_by_someone_else_is_forgotten() -> void:
	var before: int = ObjectPool.get_active_count()
	var got: Node = ObjectPool.acquire(_scene)
	got.free()
	assert_eq(ObjectPool.get_active_count(), before, "un nodo que no existe no esta activo")
	ObjectPool.release_all()
	assert_eq(ObjectPool.get_free_count(_scene), 0, "y no vuelve a la lista como basura")


func test_release_all_returns_every_lent_node() -> void:
	var a: Node = ObjectPool.acquire(_scene)
	var b: Node = ObjectPool.acquire(_scene)
	ObjectPool.release_all()
	assert_eq(ObjectPool.get_free_count(_scene), 2)
	assert_false(ObjectPool._in_use.has(a))
	assert_false(ObjectPool._in_use.has(b))


func test_a_null_scene_is_an_error_not_a_crash() -> void:
	assert_null(ObjectPool.acquire(null))
	ObjectPool.prewarm(null, 3)
	assert_push_error_count(2)
