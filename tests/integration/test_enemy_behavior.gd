extends GutTest
## Does a spawned enemy actually chase the player? Guards the whole chain:
## pooling -> setup -> behavior tree instantiation -> leaf ticks -> movement.

var _player: CharacterBody3D
var _enemy: Enemy


func before_each() -> void:
	_player = CharacterBody3D.new()
	_player.add_to_group(&"player")
	add_child_autofree(_player)
	_player.global_position = Vector3(0, 0, -20)

	var scene: PackedScene = load("res://scenes/enemies/enemy.tscn")
	_enemy = ObjectPool.acquire(scene) as Enemy
	_enemy.setup(load("res://data/enemies/rusher.tres"), Vector3.ZERO)


func after_each() -> void:
	ObjectPool.release_all()
	ObjectPool.clear()


func test_enemy_is_active_after_setup() -> void:
	assert_true(_enemy.is_active, "setup() must arm the enemy")
	assert_not_null(_enemy.data, "data")


func test_enemy_finds_the_player() -> void:
	assert_not_null(_enemy.get_player(), "player group lookup")
	assert_almost_eq(_enemy.get_distance_to_player(), 20.0, 0.5)


func test_behavior_tree_is_instantiated_with_the_enemy_as_actor() -> void:
	var holder: Node = _enemy.tree_holder
	assert_eq(holder.get_child_count(), 1, "one tree under the holder")
	var tree := holder.get_child(0) as BeehaveTree
	assert_not_null(tree, "the tree is a BeehaveTree")
	assert_eq(tree.actor, _enemy, "actor must be the enemy, not the holder")


func test_behavior_tree_ticks() -> void:
	var tree := _enemy.tree_holder.get_child(0) as BeehaveTree
	await wait_physics_frames(5)
	assert_ne(tree.status, -1, "the tree must have ticked at least once")


func test_enemy_moves_toward_the_player() -> void:
	var start: Vector3 = _enemy.global_position
	await wait_physics_frames(20)
	var moved: float = Vector2(_enemy.global_position.x - start.x,
		_enemy.global_position.z - start.z).length()
	assert_gt(moved, 0.5, "the rusher should have closed distance")
	assert_lt(_enemy.global_position.z, start.z, "it should move toward the player")


func test_enemy_paths_through_the_real_arena() -> void:
	# The isolated test above exercises the straight-line fallback. This one puts an
	# enemy on the actual baked navmesh, which is where the freeze was reported.
	var arena: Node3D = add_child_autofree(
		load("res://scenes/arena/greybox_arena.tscn").instantiate())
	await wait_physics_frames(3)

	_player.global_position = Vector3(0, 1, 20)
	var enemy := ObjectPool.acquire(load("res://scenes/enemies/enemy.tscn")) as Enemy
	enemy.setup(load("res://data/enemies/rusher.tres"), Vector3(0, 1, -10))

	var start: Vector3 = enemy.global_position
	await wait_physics_frames(30)

	var moved: float = Vector2(enemy.global_position.x - start.x,
		enemy.global_position.z - start.z).length()
	assert_gt(moved, 1.0, "an enemy on the navmesh must close distance, not stand still")
	assert_true(arena.is_inside_tree())
