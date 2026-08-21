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
	for archetype: String in ["rusher", "ranger", "elite", "healer", "summoner", "bomber", "environmental"]:
		var data: EnemyData = load("res://data/enemies/%s.tres" % archetype)
		if not data.can_jump:
			continue
		# Peak of a ballistic hop under the enemy's own gravity.
		var peak: float = (data.jump_velocity * data.jump_velocity) / (2.0 * Enemy.GRAVITY)
		assert_gt(peak, data.max_step_height,
			"%s claims a %.1fm step but can only reach %.2fm" % [
				archetype, data.max_step_height, peak])


# ----------------------------------------------------------------- ledges

## The reported bug, reproduced: a ramp is a rotated box, so head-on it is a slope
## move_and_slide climbs, and from the side it is a vertical edge that stops a
## CharacterBody3D dead however low it is.
func test_enemy_steps_onto_a_ramp_from_the_side() -> void:
	# A shallow ramp running along X, approached across its edge from +Z.
	var ramp := _make_box(Vector3(14, 0.5, 6), Vector3(0, 0.25, 0))
	_player.global_position = Vector3(0, 0.6, -1)
	_enemy = _spawn("rusher", Vector3(0, 0.5, 7))

	await wait_seconds(4.0)
	assert_gt(_enemy.global_position.y, 0.3,
		"the enemy should have stepped up onto the ledge, not stalled beside it")
	assert_true(ramp.is_inside_tree())


func test_enemy_still_walks_up_a_slope_head_on() -> void:
	# The case that already worked has to keep working.
	# +15 degrees drops the near (+z) end below the floor and lifts the far end, so
	# the enemy meets the sloped face. Negative would present its 2.5m end cap - a
	# wall, which it would be right to refuse.
	var slope := _make_box(Vector3(8, 0.4, 12), Vector3(0, 1.0, -6))
	slope.rotation.x = deg_to_rad(15.0)
	_player.global_position = Vector3(0, 2.6, -11)
	_enemy = _spawn("rusher", Vector3(0, 0.5, 3))

	await wait_seconds(4.0)
	assert_gt(_enemy.global_position.y, 1.0, "head-on approach still climbs")


func test_a_ledge_taller_than_the_step_is_not_climbed() -> void:
	# Above max_auto_step it is a wall, and the enemy should route around rather
	# than teleport up it.
	_make_box(Vector3(14, 3.0, 2), Vector3(0, 1.5, 0))
	_player.global_position = Vector3(0, 0.5, -6)
	_enemy = _spawn("rusher", Vector3(0, 0.5, 4))

	await wait_seconds(2.0)
	assert_lt(_enemy.global_position.y, 1.5,
		"a 3m wall is not a step, however hard it is pushed against")


## The step height is a promise the navmesh already made on the enemy's behalf.
func test_step_height_covers_what_the_navmesh_bake_assumes() -> void:
	var navmesh: NavigationMesh = load("res://scenes/arena/greybox_arena_navmesh.tres")
	for archetype: String in ["rusher", "ranger", "elite", "healer", "summoner", "bomber", "environmental"]:
		var data: EnemyData = load("res://data/enemies/%s.tres" % archetype)
		assert_true(data.max_auto_step >= navmesh.agent_max_climb,
			"%s can step %.2fm but the bake hands out paths with %.2fm climbs" % [
				archetype, data.max_auto_step, navmesh.agent_max_climb])


# ------------------------------------------------------------- reach vs distance

## Reported as "taking damage with no enemy in range". Distance alone is not reach:
## an enemy wedged under a platform is within melee distance of someone standing on
## top of it, and would otherwise hit through the floor.
func test_melee_does_not_pass_through_a_floor() -> void:
	_make_box(Vector3(20, 0.5, 20), Vector3(0, 2.0, 0))     # platform overhead
	_player.global_position = Vector3(0, 2.4, 0)             # standing on it
	var health := HealthComponent.new()
	health.max_health = 100.0
	_player.add_child(health)

	_enemy = _spawn("rusher", Vector3(0, 0.2, 0))            # directly underneath
	await wait_physics_frames(2)
	assert_lt(_enemy.global_position.distance_to(_player.global_position), 3.0,
		"the two are within melee distance, which is the point")

	for i: int in 20:
		_enemy.deal_melee_damage()
		await wait_physics_frames(1)
	assert_eq(health.current_health, health.max_health,
		"a floor between them means the hit does not land")


func test_melee_lands_with_a_clear_line() -> void:
	_player.global_position = Vector3(0, 0.5, 1.5)
	var health := HealthComponent.new()
	health.max_health = 100.0
	_player.add_child(health)

	_enemy = _spawn("rusher", Vector3(0, 0.5, 0))
	await wait_physics_frames(2)
	_enemy.deal_melee_damage()
	assert_lt(health.current_health, health.max_health,
		"nothing in the way means the hit lands")
