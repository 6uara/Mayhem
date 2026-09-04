extends Node
## Generic pooling for high-churn nodes: projectiles, impact VFX, damage numbers, enemies.
## Pooled scenes must expose `_on_acquired()` / `_on_released()` if they need reset logic.

const RELEASED_GROUP: StringName = &"pooled_released"

var _free: Dictionary = {}      # PackedScene -> Array[Node]
var _in_use: Dictionary = {}    # Node -> PackedScene
var _containers: Dictionary = {}  # PackedScene -> Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# Public API

## Instantiate `count` copies up front so the first shot never hitches.
func prewarm(scene: PackedScene, count: int) -> void:
	if scene == null:
		push_error("ObjectPool.prewarm: null scene")
		return
	var pool: Array = _get_free_list(scene)
	for _i: int in count:
		var instance: Node = _instantiate(scene)
		_deactivate(instance)
		pool.push_back(instance)


## Take a node out of the pool. It is already added to the scene tree.
func acquire(scene: PackedScene) -> Node:
	if scene == null:
		push_error("ObjectPool.acquire: null scene")
		return null
	var pool: Array = _get_free_list(scene)
	var instance: Node
	while instance == null and not pool.is_empty():
		var candidate: Variant = pool.pop_back()
		if is_instance_valid(candidate):
			instance = candidate as Node
	if instance == null:
		instance = _instantiate(scene)
	_in_use[instance] = scene
	_activate(instance)
	return instance


## Return a node to its pool. Safe to call twice.
func release(instance: Node) -> void:
	if instance == null or not is_instance_valid(instance):
		return
	if not _in_use.has(instance):
		return
	var scene: PackedScene = _in_use[instance]
	_in_use.erase(instance)
	_deactivate(instance)
	_get_free_list(scene).push_back(instance)


## Release everything currently active - call between runs.
func release_all() -> void:
	for instance: Node in _in_use.keys():
		release(instance)


## Free every pooled node and drop the pools entirely.
func clear() -> void:
	release_all()
	for scene: PackedScene in _free.keys():
		for instance: Variant in _free[scene]:
			if is_instance_valid(instance):
				(instance as Node).queue_free()
	_free.clear()
	for scene: PackedScene in _containers.keys():
		var container: Node = _containers[scene]
		if is_instance_valid(container):
			container.queue_free()
	_containers.clear()


func get_free_count(scene: PackedScene) -> int:
	return _get_free_list(scene).size()


func get_active_count() -> int:
	return _in_use.size()


# Private

func _get_free_list(scene: PackedScene) -> Array:
	if not _free.has(scene):
		_free[scene] = []
	return _free[scene]


func _instantiate(scene: PackedScene) -> Node:
	var instance: Node = scene.instantiate()
	_get_container(scene).add_child(instance)
	return instance


func _get_container(scene: PackedScene) -> Node:
	if _containers.has(scene) and is_instance_valid(_containers[scene]):
		return _containers[scene]
	var container := Node.new()
	container.name = "Pool_%s" % scene.resource_path.get_file().get_basename()
	add_child(container)
	_containers[scene] = container
	return container


func _activate(instance: Node) -> void:
	instance.remove_from_group(RELEASED_GROUP)
	# No PROCESS_MODE_INHERIT: el contenedor cuelga del pool, que es
	# PROCESS_MODE_ALWAYS para poder pooler durante una pausa. Heredar eso dejaba a
	# cada enemigo, proyectil y frasco activo corriendo igual con el arbol
	# pausado - el jugador se congelaba y todo lo demas lo seguia matando.
	# PAUSABLE es el modo normal de un nodo de juego: corre salvo que el arbol
	# este pausado, sin importar que el ancestro este marcado ALWAYS.
	instance.process_mode = Node.PROCESS_MODE_PAUSABLE
	if instance is Node3D:
		(instance as Node3D).visible = true
	if instance.has_method(&"_on_acquired"):
		instance.call(&"_on_acquired")


func _deactivate(instance: Node) -> void:
	if instance.has_method(&"_on_released"):
		instance.call(&"_on_released")
	instance.process_mode = Node.PROCESS_MODE_DISABLED
	if instance is Node3D:
		var node_3d := instance as Node3D
		node_3d.visible = false
		node_3d.global_position = Vector3(0.0, -10000.0, 0.0)
	instance.add_to_group(RELEASED_GROUP)
