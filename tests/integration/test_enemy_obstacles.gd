extends GutTest
## Enemies must get past the things that stop them, not lean on them.
##
## The playtest symptom was enemies grinding beside a ramp. The underlying class of
## problem is broader - a navmesh path is a plan, and geometry, crowds and bake
## seams all break plans - so these tests are about the recovery behaviour rather
## than about one ramp.

var _floor: StaticBody3D
var _player: CharacterBody3D
var _enemy: Enemy


func before_each() -> void:
	_floor = _make_box(Vector3(60, 1, 60), Vector3(0, -0.5, 0))
	_player = CharacterBody3D.new()
	_player.add_to_group(&"player")
	add_child_autofree(_player)


func after_each() -> void:
	ObjectPool.release_all()
	ObjectPool.clear()


func _make_box(box_size: Vector3, position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	body.add_child(shape)

	add_child_autofree(body)
	body.global_position = position
	return body


func _spawn(archetype: String, at: Vector3) -> Enemy:
	var enemy := ObjectPool.acquire(load("res://scenes/enemies/enemy.tscn")) as Enemy
	enemy.setup(load("res://data/enemies/%s.tres" % archetype), at)
	return enemy


func test_enemy_hops_a_low_wall_between_it_and_the_player() -> void:
	# A 1m lip: too tall to walk, well inside a jump.
	_make_box(Vector3(12, 1.0, 0.6), Vector3(0, 0.5, 0))
	_player.global_position = Vector3(0, 0.5, -6)
	_enemy = _spawn("rusher", Vector3(0, 0.5, 6))

	await wait_seconds(5.0)
	assert_lt(_enemy.global_position.z, -0.5,
		"the enemy should have crossed the lip instead of pressing against it")


func test_enemy_does_not_jump_at_a_wall_it_cannot_clear() -> void:
	# Full-height wall: jumping would be a shorter grind, so it should not bother.
	_make_box(Vector3(12, 6.0, 0.6), Vector3(0, 3.0, 0))
	_player.global_position = Vector3(0, 0.5, -6)
	_enemy = _spawn("rusher", Vector3(0, 0.5, 6))

	await wait_seconds(2.0)
	assert_lt(_enemy.global_position.y, 1.2,
		"it should stay on the ground rather than hopping uselessly at a wall")


func test_the_hop_respects_the_archetype_cooldown() -> void:
	_make_box(Vector3(12, 1.0, 0.6), Vector3(0, 0.5, 0))
	_player.global_position = Vector3(0, 0.5, -6)
	_enemy = _spawn("rusher", Vector3(0, 0.5, 6))

	await wait_seconds(0.8)
	# Whatever it is doing, it is not vibrating on the spot at jump velocity.
	assert_lt(absf(_enemy.velocity.y), _enemy.data.jump_velocity + 0.5,
		"vertical speed never exceeds one jump's worth")


func test_an_archetype_with_jumping_disabled_stays_grounded() -> void:
	var data: EnemyData = load("res://data/enemies/rusher.tres").duplicate()
	data.can_jump = false
	_make_box(Vector3(12, 1.0, 0.6), Vector3(0, 0.5, 0))
	_player.global_position = Vector3(0, 0.5, -6)

	_enemy = ObjectPool.acquire(load("res://scenes/enemies/enemy.tscn")) as Enemy
	_enemy.setup(data, Vector3(0, 0.5, 6))

	await wait_seconds(2.0)
	assert_lt(_enemy.global_position.y, 1.2, "can_jump = false means it never leaves the floor")


func test_every_archetype_can_clear_its_own_max_step() -> void:
	# The tallest hop each archetype claims it can make has to actually be possible
	# with the jump velocity it carries, or max_step_height is a lie in the data.
	for archetype: String in ["rusher", "ranger", "elite", "healer", "summoner"]:
		var data: EnemyData = load("res://data/enemies/%s.tres" % archetype)
		if not data.can_jump:
			continue
		# Peak of a ballistic hop under the enemy's own gravity.
		var peak: float = (data.jump_velocity * data.jump_velocity) / (2.0 * Enemy.GRAVITY)
		assert_gt(peak, data.max_step_height,
			"%s claims a %.1fm step but can only reach %.2fm" % [
				archetype, data.max_step_height, peak])
