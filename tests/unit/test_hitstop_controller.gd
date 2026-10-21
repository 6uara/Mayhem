extends GutTest
## HitstopController drives Engine.time_scale, which is truly global engine state -
## every test here must leave it at 1.0, or every other test in the suite that
## measures anything by elapsed frames or delta silently runs in slow motion.

var _hitstop: HitstopController


func before_each() -> void:
	_hitstop = HitstopController.new()
	# The headless runner's frame rate says nothing about the player's machine;
	# the low-FPS skip has its own test that sets this back.
	_hitstop.light_min_fps = 0.0
	add_child_autofree(_hitstop)
	await wait_physics_frames(1)


func after_each() -> void:
	Engine.time_scale = 1.0


func _kill() -> void:
	EventBus.kill_scored.emit(&"rusher", Vector3.ZERO, false, 10)


func test_a_landed_hit_dips_time_scale() -> void:
	EventBus.damage_dealt.emit(null, 10.0, false)
	assert_almost_eq(Engine.time_scale, _hitstop.scale, 0.001)


func test_a_body_hit_dips_less_than_a_headshot() -> void:
	assert_gt(_hitstop.scale, _hitstop.full_scale,
		"a plain hit slows the world, it must not stop it like a headshot does")
	EventBus.damage_dealt.emit(null, 10.0, true)
	assert_almost_eq(Engine.time_scale, _hitstop.full_scale, 0.001)


func test_a_kill_gets_the_full_dip() -> void:
	_kill()
	assert_almost_eq(Engine.time_scale, _hitstop.full_scale, 0.001)


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
	Engine.time_scale = 1.0
	_hitstop._restore()

	var before_head: int = Time.get_ticks_usec()
	EventBus.damage_dealt.emit(null, 10.0, true)
	var headshot_window: int = _hitstop._end_at_usec - before_head

	assert_gt(headshot_window, body_shot_window,
		"a headshot must be scheduled to hold the dip longer than a body shot")


## The freeze the slow machines reported: every bullet of a burst refreshed the
## dip, so holding the trigger kept the game in it.
func test_a_burst_of_body_hits_does_not_extend_the_dip() -> void:
	EventBus.damage_dealt.emit(null, 10.0, false)
	var first_end: int = _hitstop._end_at_usec
	await wait_physics_frames(1)

	EventBus.damage_dealt.emit(null, 10.0, false)
	assert_eq(_hitstop._end_at_usec, first_end,
		"a body hit landing mid-dip must share it, not push its end forward")


func test_a_body_hit_right_after_a_dip_waits_for_the_rearm() -> void:
	EventBus.damage_dealt.emit(null, 10.0, false)
	await _wait_until(func() -> bool: return Engine.time_scale >= 1.0)

	EventBus.damage_dealt.emit(null, 10.0, false)
	assert_almost_eq(Engine.time_scale, 1.0, 0.001,
		"a fast weapon must not chain light dips back to back")


func test_a_kill_deepens_a_light_dip_already_running() -> void:
	EventBus.damage_dealt.emit(null, 10.0, false)
	_kill()
	assert_almost_eq(Engine.time_scale, _hitstop.full_scale, 0.001)

	EventBus.damage_dealt.emit(null, 10.0, false)
	assert_almost_eq(Engine.time_scale, _hitstop.full_scale, 0.001,
		"a light hit landing inside a full dip must not make it shallower")


func test_a_slow_frame_rate_skips_the_light_dip() -> void:
	_hitstop.light_min_fps = 100_000.0
	EventBus.damage_dealt.emit(null, 10.0, false)
	assert_almost_eq(Engine.time_scale, 1.0, 0.001,
		"below the threshold a light dip is only a dropped frame")

	_kill()
	assert_almost_eq(Engine.time_scale, _hitstop.full_scale, 0.001,
		"the full dip on a kill still plays on a slow machine")


func test_leaving_the_tree_restores_time_scale() -> void:
	EventBus.damage_dealt.emit(null, 10.0, false)
	assert_lt(Engine.time_scale, 1.0, "precondition")
	_hitstop.queue_free()
	await wait_physics_frames(1)
	assert_almost_eq(Engine.time_scale, 1.0, 0.001,
		"a controller that goes away must not leave the game in slow motion")
