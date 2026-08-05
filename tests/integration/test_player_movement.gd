extends GutTest
## The feel guarantees of player movement.
##
## These are the properties a playtest complains about but a build cannot check on
## its own: whether a jump has weight, whether an input made near a ledge survives,
## and whether the cosmetic layer has quietly started steering bullets. Feel is
## tuned by hand, but the shape of it is testable, and none of it was covered before.

const FLOOR_Y: float = 0.0

var _player: Player
var _feel: CameraFeelComponent


func before_each() -> void:
	_make_floor()
	_player = add_child_autofree(load("res://scenes/player/player.tscn").instantiate())
	_player.global_position = Vector3(0, FLOOR_Y + 0.1, 0)
	_feel = _player.get_node("CameraFeelComponent")
	await wait_physics_frames(6)


func after_each() -> void:
	# Input is global state: a key left down leaks into the next test.
	for action: String in ["jump", "crouch_slide", "move_forward"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)


func _make_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	add_child_autofree(floor_body)


## Peak height reached over `frames`, measured from wherever the player starts.
func _apex_over(frames: int) -> float:
	var start: float = _player.global_position.y
	var peak: float = 0.0
	for _i: int in frames:
		await wait_physics_frames(1)
		peak = maxf(peak, _player.global_position.y - start)
	return peak


# ------------------------------------------------------------------- weight

## The anti-floaty guarantee. A symmetric arc is the single loudest source of
## "floating": weight is sold on the way down, so the descent must accelerate
## harder than the climb did.
func test_falling_is_heavier_than_rising() -> void:
	var movement: MovementComponent = _player.movement
	_player.global_position = Vector3(0, FLOOR_Y + 20.0, 0)
	await wait_physics_frames(2)

	_player.velocity = Vector3(0, 6.0, 0)
	var rising_before: float = _player.velocity.y
	await wait_physics_frames(1)
	var rising_loss: float = rising_before - _player.velocity.y

	_player.velocity = Vector3(0, -6.0, 0)
	var falling_before: float = _player.velocity.y
	await wait_physics_frames(1)
	var falling_loss: float = falling_before - _player.velocity.y

	assert_gt(falling_loss, rising_loss * 1.3,
		"the fall must accelerate harder than the rise (scale %0.2f)"
			% movement.fall_gravity_scale)


## A jump too short to clear a knee-height ledge reads as a movement bug, not
## restraint - pins the apex well above that floor so it can't regress silently.
func test_a_normal_jump_clears_a_knee_height_ledge() -> void:
	var movement: MovementComponent = _player.movement
	Input.action_press("jump")
	var apex: float = await _apex_over(30)
	Input.action_release("jump")

	assert_gt(apex, 1.0,
		"apex %0.2fm from jump_velocity %0.1f clears less than a 1m ledge"
			% [apex, movement.jump_velocity])


func test_a_tapped_jump_is_shorter_than_a_held_one() -> void:
	Input.action_press("jump")
	var held: float = await _apex_over(24)
	Input.action_release("jump")
	await wait_physics_frames(30)

	_player.global_position = Vector3(0, FLOOR_Y + 0.1, 0)
	_player.velocity = Vector3.ZERO
	await wait_physics_frames(6)

	Input.action_press("jump")
	await wait_physics_frames(2)
	Input.action_release("jump")
	var tapped: float = await _apex_over(24)

	assert_lt(tapped, held * 0.85,
		"releasing jump early has to cut the climb (tapped %0.2fm vs held %0.2fm)"
			% [tapped, held])


## CLAUDE.md 5.2 makes momentum a resource the player keeps. Landing may punch the
## camera, but it must never quietly tax the speed that was earned to get there.
func test_landing_costs_no_horizontal_speed() -> void:
	_player.global_position = Vector3(0, FLOOR_Y + 3.0, 0)
	_player.velocity = Vector3(9.0, 0.0, 0.0)
	await wait_physics_frames(2)
	var before: float = Vector2(_player.velocity.x, _player.velocity.z).length()

	for _i: int in 40:
		await wait_physics_frames(1)
		if _player.is_on_floor():
			break

	var after: float = Vector2(_player.velocity.x, _player.velocity.z).length()
	assert_gt(after, before * 0.9,
		"a landing must not eat momentum (%0.1f -> %0.1f)" % [before, after])


# -------------------------------------------------------------- responsiveness

func test_coyote_time_allows_a_jump_just_after_leaving_a_ledge() -> void:
	# Step off into open air without jumping, then ask for one.
	_player.global_position = Vector3(0, FLOOR_Y + 0.1, 0)
	await wait_physics_frames(4)
	_player.global_position = Vector3(200, FLOOR_Y + 4.0, 200)  # nothing underneath
	await wait_physics_frames(2)

	assert_false(_player.is_on_floor(), "precondition: airborne")
	Input.action_press("jump")
	await wait_physics_frames(1)
	Input.action_release("jump")

	assert_gt(_player.velocity.y, 0.0,
		"a jump inside the coyote window still has to launch")


func test_coyote_does_not_hand_out_a_second_jump() -> void:
	Input.action_press("jump")
	await wait_physics_frames(2)
	Input.action_release("jump")
	await wait_physics_frames(2)

	var rising: float = _player.velocity.y
	assert_gt(rising, 0.0, "precondition: the first jump left the ground")

	Input.action_press("jump")
	await wait_physics_frames(1)
	Input.action_release("jump")
	assert_lt(_player.velocity.y, rising + 0.01,
		"the second press must not re-launch in mid air")


func test_a_jump_pressed_before_landing_still_fires() -> void:
	_player.global_position = Vector3(0, FLOOR_Y + 1.2, 0)
	_player.velocity = Vector3.ZERO
	await wait_physics_frames(2)

	# Press while still falling, then let go: by the time the floor arrives the
	# button is long released, so only the buffer can save this input.
	Input.action_press("jump")
	await wait_physics_frames(1)
	Input.action_release("jump")

	var launched: bool = false
	for _i: int in 30:
		await wait_physics_frames(1)
		if _player.velocity.y > 0.5:
			launched = true
			break
	assert_true(launched, "a jump buffered before touchdown has to survive the landing")


# --------------------------------------------------------------- aim safety

## The whole cosmetic layer rests on this: the bob node sits *below* the aim pivot,
## so nothing it does can reach a bullet. If someone later moves bob onto HeadPivot
## to save a node, this fails rather than silently making the gun lie.
func test_view_bob_can_never_move_the_aim() -> void:
	var before: Transform3D = _player.get_aim_transform()

	_feel.view_node.position = Vector3(0.5, -0.4, 0.3)
	_feel.view_node.rotation_degrees = Vector3(0, 0, 25.0)
	await wait_physics_frames(2)

	var after: Transform3D = _player.get_aim_transform()
	assert_almost_eq(after.origin, before.origin, Vector3.ONE * 0.0001,
		"bob must not move where shots come from")
	assert_almost_eq(-after.basis.z, -before.basis.z, Vector3.ONE * 0.0001,
		"lean must not move where shots go")


func test_the_bob_node_sits_under_the_aim_pivot() -> void:
	assert_true(_player.head.is_ancestor_of(_feel.view_node),
		"the cosmetic node has to hang below the aim pivot, not above it")


# ---------------------------------------------------------------- step cycle

func test_standing_still_produces_no_footsteps() -> void:
	watch_signals(_feel)
	_player.velocity = Vector3.ZERO
	await wait_physics_frames(20)
	assert_signal_emit_count(_feel, "stepped", 0,
		"a stationary player does not walk")


func test_running_produces_footsteps() -> void:
	watch_signals(_feel)
	for _i: int in 40:
		# Re-assert speed each frame: ground friction would otherwise stop them.
		_player.velocity.x = 8.0
		await wait_physics_frames(1)
	assert_gt(get_signal_emit_count(_feel, "stepped"), 0,
		"covering ground has to produce steps")


## Phase advances with distance covered, not with the clock - so the same span of
## time spent moving faster owes more steps. The counts are read as a running total
## and differenced, because the signal watcher accumulates across a test.
func test_footsteps_track_distance_not_time() -> void:
	watch_signals(_feel)
	for _i: int in 30:
		_player.velocity.x = 3.0
		await wait_physics_frames(1)
	var slow: int = get_signal_emit_count(_feel, "stepped")

	for _i: int in 30:
		_player.velocity.x = 9.0
		await wait_physics_frames(1)
	var fast: int = get_signal_emit_count(_feel, "stepped") - slow

	assert_gt(fast, slow,
		"equal time at triple the speed must mean more steps (%d fast vs %d slow)"
			% [fast, slow])


# ------------------------------------------------------------- movement VFX

## A dash trail that outlives the dash it marks would keep burning on a charge
## the player has already spent, so it fires once, off the same signal the HUD's
## charge pips read - not off polling movement.state every frame.
func test_dashing_bursts_the_dash_trail() -> void:
	var trail: GPUParticles3D = _player.get_node("DashTrail")
	assert_false(trail.emitting, "precondition: no trail before any dash")

	EventBus.dash_used.emit(2)
	assert_true(trail.emitting, "a spent charge has to show as a trail burst")


## Sparks are the tell that a slide is live, so they must track the state exactly:
## on for every physics tick spent sliding, and gone the instant the player is not.
func test_sliding_streams_sparks_only_while_sliding() -> void:
	var sparks: GPUParticles3D = _player.get_node("SlideSparks")
	var movement: MovementComponent = _player.movement
	assert_false(sparks.emitting, "precondition: no sparks before any slide")

	movement.state = MovementComponent.State.SLIDING
	assert_true(sparks.emitting, "sliding has to read as sparks underfoot")

	movement.state = MovementComponent.State.GROUNDED
	assert_false(sparks.emitting, "standing up has to cut the sparks immediately")
