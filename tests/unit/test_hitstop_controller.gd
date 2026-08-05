extends GutTest
## HitstopController drives Engine.time_scale, which is truly global engine state -
## every test here must leave it at 1.0, or every other test in the suite that
## measures anything by elapsed frames or delta silently runs in slow motion.

var _hitstop: HitstopController


func before_each() -> void:
	_hitstop = add_child_autofree(HitstopController.new())
	await wait_physics_frames(1)


func after_each() -> void:
	Engine.time_scale = 1.0


func test_a_landed_hit_dips_time_scale() -> void:
	EventBus.damage_dealt.emit(null, 10.0, false)
	assert_almost_eq(Engine.time_scale, _hitstop.scale, 0.001)


func test_zero_damage_does_not_trigger_hitstop() -> void:
	# A hit that landed on an already-dead or invulnerable target still emits the
	# signal with amount 0.0 - that must not read as an impact.
	EventBus.damage_dealt.emit(null, 0.0, false)
	assert_almost_eq(Engine.time_scale, 1.0, 0.001)


## Idle _process frames don't reliably advance under the headless test runner
## (the same reason GUT itself deprecated wait_frames in favour of
## wait_physics_frames) - HitstopController ticks on _physics_process for
## exactly that reason. Waits here poll the real condition against a generous
## physics-frame ceiling rather than assuming any fixed number of frames maps
## to a fixed span of wall-clock time.
func _wait_until(condition: Callable, max_physics_frames: int = 300) -> void:
	for _i: int in max_physics_frames:
		if condition.call():
			return
		await wait_physics_frames(1)


func test_time_scale_recovers_on_its_own() -> void:
	EventBus.damage_dealt.emit(null, 10.0, false)
	assert_lt(Engine.time_scale, 1.0, "precondition: the dip actually happened")

	await _wait_until(func() -> bool: return Engine.time_scale >= 1.0)
	assert_almost_eq(Engine.time_scale, 1.0, 0.001)


## The harder shot gets the longer freeze - the payoff for landing it. Reads the
## scheduled end time directly rather than waiting it out twice in real time,
## which is what the config itself is for.
func test_a_headshot_holds_the_dip_longer_than_a_body_shot() -> void:
	var before_body: int = Time.get_ticks_usec()
	EventBus.damage_dealt.emit(null, 10.0, false)
	var body_shot_window: int = _hitstop._end_at_usec - before_body

	var before_head: int = Time.get_ticks_usec()
	EventBus.damage_dealt.emit(null, 10.0, true)
	var headshot_window: int = _hitstop._end_at_usec - before_head

	assert_gt(headshot_window, body_shot_window,
		"a headshot must be scheduled to hold the dip longer than a body shot")


## A second hit landing mid-dip refreshes the window rather than stacking on top
## of it - hitstop is a state, not an accumulator.
func test_a_second_hit_refreshes_rather_than_stacks() -> void:
	EventBus.damage_dealt.emit(null, 10.0, false)
	var first_end: int = _hitstop._end_at_usec
	await wait_physics_frames(1)

	EventBus.damage_dealt.emit(null, 10.0, false)
	var second_end: int = _hitstop._end_at_usec

	assert_gt(second_end, first_end,
		"a hit landing mid-dip must push the end time forward, not leave it alone")


func test_leaving_the_tree_restores_time_scale() -> void:
	EventBus.damage_dealt.emit(null, 10.0, false)
	assert_lt(Engine.time_scale, 1.0, "precondition")
	_hitstop.queue_free()
	await wait_physics_frames(1)
	assert_almost_eq(Engine.time_scale, 1.0, 0.001,
		"a controller that goes away must not leave the game in slow motion")
