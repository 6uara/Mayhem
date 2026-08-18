extends GutTest
## The walk is computed rather than authored, so what is worth pinning is the
## contract that buys: the cycle is tied to ground covered, and it stops when the
## enemy does.


func _spawn(id: String) -> Enemy:
	var enemy: Enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	add_child_autofree(enemy)
	await wait_physics_frames(1)
	enemy.setup(load("res://data/enemies/%s.tres" % id), Vector3.ZERO)
	enemy.set_physics_process(false)
	await wait_physics_frames(1)
	return enemy


func _gait_of(enemy: Enemy) -> LeggedGait:
	for child: Node in enemy.get_children():
		var gait := child as LeggedGait
		if gait != null:
			return gait
	return null


func test_a_model_with_legs_gets_a_gait() -> void:
	var enemy: Enemy = await _spawn("rusher")
	assert_not_null(_gait_of(enemy), "the spider bot walks")


## An archetype still wearing its capsule has nothing to walk with, and the
## component is dropped rather than left running on every enemy in the wave.
func test_a_capsule_archetype_gets_none() -> void:
	var enemy: Enemy = await _spawn("ranger")
	assert_null(_gait_of(enemy), "no legs, no gait")


## The whole reason for computing the walk instead of playing it: a clip runs at
## the speed it was authored at, and this enemy's speed is not a constant - a
## slow field halves it. Tying the cycle to distance is what keeps the feet from
## sliding when that happens.
func test_the_cycle_follows_distance_not_time() -> void:
	var enemy: Enemy = await _spawn("rusher")
	var gait: LeggedGait = _gait_of(enemy)

	# Same ground covered, one at double the speed for half as long.
	enemy.velocity = Vector3(0.0, 0.0, -4.0)
	for _step: int in 60:
		gait._physics_process(1.0 / 60.0)
	var slow_phase: float = gait._phase

	gait._phase = 0.0
	enemy.velocity = Vector3(0.0, 0.0, -8.0)
	for _step: int in 30:
		gait._physics_process(1.0 / 60.0)

	assert_almost_eq(gait._phase, slow_phase, 0.001,
		"one metre of ground is one step's worth of cycle, at any speed")


func test_standing_still_settles_the_legs() -> void:
	var enemy: Enemy = await _spawn("rusher")
	var gait: LeggedGait = _gait_of(enemy)

	enemy.velocity = Vector3(0.0, 0.0, -7.0)
	for _step: int in 30:
		gait._physics_process(1.0 / 60.0)
	assert_gt(gait._weight, 0.9, "walking, so the legs are swinging")

	enemy.velocity = Vector3.ZERO
	for _step: int in 30:
		gait._physics_process(1.0 / 60.0)
	assert_eq(gait._weight, 0.0, "stopped, so they come back to rest")
