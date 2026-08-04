extends GutTest
## The arena's interactive elements. These are gameplay, not decoration: a hazard
## that damages outside its decal or a platform whose warning is inconsistent breaks
## the contract the player learns the arena through.


func _instance(path: String) -> Node:
	return add_child_autofree(load(path).instantiate())


## A body the hazard can see, without the player's gravity - the real player would
## simply fall out of the volume in a test with no floor under it.
func _make_target() -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.add_to_group(&"player")
	body.collision_layer = PhysicsLayers.PLAYER

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.4
	shape.shape = capsule
	shape.position.y = 0.9
	body.add_child(shape)

	var health := HealthComponent.new()
	health.max_health = 100.0
	body.add_child(health)

	add_child_autofree(body)
	return body


# --------------------------------------------------------------- the colour law

## Cyan usable, acid hurts, amber take, magenta spawn - and no colour ever means
## two things (SPEC-VIEWMODELS 3.2).
func test_every_element_declares_the_right_meaning() -> void:
	var expected: Dictionary = {
		"res://scenes/arena/grapple_anchor.tscn": TelegraphComponent.Meaning.TRAVERSAL,
		"res://scenes/arena/moving_platform.tscn": TelegraphComponent.Meaning.TRAVERSAL,
		"res://scenes/arena/zip_line.tscn": TelegraphComponent.Meaning.TRAVERSAL,
		"res://scenes/arena/disappearing_platform.tscn": TelegraphComponent.Meaning.TRAVERSAL,
		"res://scenes/arena/hazard_zone.tscn": TelegraphComponent.Meaning.HAZARD,
	}
	for path: String in expected:
		var element: Node = _instance(path)
		var telegraph: TelegraphComponent = element.get_node("Telegraph")
		assert_eq(telegraph.meaning, expected[path], "%s meaning" % path)


func test_the_four_meanings_never_share_a_colour() -> void:
	var seen: Array[Color] = []
	for meaning: int in [TelegraphComponent.Meaning.TRAVERSAL,
			TelegraphComponent.Meaning.HAZARD, TelegraphComponent.Meaning.PICKUP,
			TelegraphComponent.Meaning.SPAWN]:
		var telegraph := TelegraphComponent.new()
		telegraph.meaning = meaning
		add_child_autofree(telegraph)
		var colour: Color = telegraph.get_color()
		assert_false(seen.has(colour), "meaning %d reuses a colour" % meaning)
		seen.push_back(colour)


# ---------------------------------------------------------------------- hazards

## The decal IS the damage footprint. A hazard that hurts outside its own decal is
## a bug, not a difficulty setting.
func test_hazard_decal_matches_its_damage_radius() -> void:
	var hazard: HazardZone = _instance("res://scenes/arena/hazard_zone.tscn")
	hazard.radius = 5.0
	await wait_physics_frames(2)

	var shape := hazard.collision.shape as CylinderShape3D
	assert_almost_eq(shape.radius, 5.0, 0.001, "collision radius")
	assert_almost_eq(hazard.decal_mesh.scale.x, 5.0, 0.001, "decal radius")
	assert_almost_eq(hazard.decal_mesh.scale.z, 5.0, 0.001, "decal radius")


## Two hazards must not share one collision shape.
##
## They did, and it corrupted the source file three times: a sub-resource authored
## in a .tscn is shared across every instance unless it says otherwise, so setting
## the radius at runtime wrote into the scene's own shape, and the editor then saved
## that value back to disk - each pass shrinking the authored hazard further. It
## fails nothing at runtime, which is what made it survive so long.
func test_each_hazard_owns_its_own_collision_shape() -> void:
	var first: HazardZone = _instance("res://scenes/arena/hazard_zone.tscn")
	var second: HazardZone = _instance("res://scenes/arena/hazard_zone.tscn")
	await wait_physics_frames(2)

	first.radius = 7.0
	second.radius = 2.0
	await wait_physics_frames(2)

	assert_ne(first.collision.shape, second.collision.shape,
		"hazards must not share a shape resource")
	assert_almost_eq((first.collision.shape as CylinderShape3D).radius, 7.0, 0.001,
		"resizing one hazard...")
	assert_almost_eq((second.collision.shape as CylinderShape3D).radius, 2.0, 0.001,
		"...must not follow the other")


## The decal is the damage footprint, so it has to sit on the damage.
func test_the_decal_sits_on_the_pool_it_marks() -> void:
	var hazard: HazardZone = _instance("res://scenes/arena/hazard_zone.tscn")
	await wait_physics_frames(2)
	assert_almost_eq(hazard.decal_mesh.position, Vector3.ZERO, Vector3.ONE * 0.05,
		"a decal offset from its own hazard is a telegraph pointing at the wrong place")


func test_hazard_warns_before_it_can_damage() -> void:
	var hazard: HazardZone = _instance("res://scenes/arena/hazard_zone.tscn")
	assert_false(hazard.is_armed, "a hazard never damages during its warning")
	assert_eq(hazard.telegraph.state, TelegraphComponent.State.WARNING)

	await wait_seconds(Tokens.HAZARD_WARNING + 0.15)
	assert_true(hazard.is_armed, "it arms once the warning has run")
	assert_eq(hazard.telegraph.state, TelegraphComponent.State.ACTIVE)


func test_hazard_damages_whatever_stands_in_it() -> void:
	var hazard: HazardZone = _instance("res://scenes/arena/hazard_zone.tscn")
	hazard.tick_interval = 0.05
	var target: CharacterBody3D = _make_target()
	target.global_position = hazard.global_position

	var health: HealthComponent = target.get_child(1)
	var before: float = health.current_health
	await wait_seconds(Tokens.HAZARD_WARNING + 0.3)
	assert_lt(health.current_health, before, "standing in acid costs health")


func test_hazard_does_not_damage_during_its_warning() -> void:
	var hazard: HazardZone = _instance("res://scenes/arena/hazard_zone.tscn")
	hazard.tick_interval = 0.05
	var target: CharacterBody3D = _make_target()
	target.global_position = hazard.global_position

	var health: HealthComponent = target.get_child(1)
	await wait_seconds(Tokens.HAZARD_WARNING * 0.6)
	assert_eq(health.current_health, health.max_health,
		"the warning is a promise: nothing is hurt until it ends")


# ------------------------------------------------------ disappearing platforms

func test_platform_starts_solid() -> void:
	var platform: DisappearingPlatform = _instance(
		"res://scenes/arena/disappearing_platform.tscn")
	assert_eq(platform.state, DisappearingPlatform.State.SOLID)
	assert_eq(platform.body.collision_layer, PhysicsLayers.WORLD)


## Same delay every time is what makes these routable at speed rather than a trap.
func test_platform_warning_lasts_the_global_constant() -> void:
	var platform: DisappearingPlatform = _instance(
		"res://scenes/arena/disappearing_platform.tscn")
	platform.trigger()
	assert_eq(platform.state, DisappearingPlatform.State.WARNING)

	await wait_seconds(Tokens.PLATFORM_WARNING * 0.5)
	assert_eq(platform.state, DisappearingPlatform.State.WARNING,
		"still solid halfway through the warning")

	await wait_seconds(Tokens.PLATFORM_WARNING * 0.5 + 0.2)
	assert_eq(platform.state, DisappearingPlatform.State.GONE)
	assert_eq(platform.body.collision_layer, 0, "gone means you fall through it")


func test_stepping_on_a_warning_platform_does_not_reset_it() -> void:
	var platform: DisappearingPlatform = _instance(
		"res://scenes/arena/disappearing_platform.tscn")
	platform.trigger()
	await wait_seconds(Tokens.PLATFORM_WARNING * 0.7)
	platform.trigger()  # a second footstep
	await wait_seconds(Tokens.PLATFORM_WARNING * 0.4)
	assert_eq(platform.state, DisappearingPlatform.State.GONE,
		"the deadline belongs to the platform, not to the last footstep")


func test_the_ghost_outline_survives_so_the_route_back_is_readable() -> void:
	var platform: DisappearingPlatform = _instance(
		"res://scenes/arena/disappearing_platform.tscn")
	platform.trigger()
	await wait_seconds(Tokens.PLATFORM_WARNING + 0.2)
	assert_true(platform.ghost_mesh.visible, "the outline stays while it is gone")
	assert_false(platform.solid_mesh.visible)


func test_platform_comes_back() -> void:
	var platform: DisappearingPlatform = _instance(
		"res://scenes/arena/disappearing_platform.tscn")
	platform.respawn_time = 0.3
	platform.trigger()
	await wait_seconds(Tokens.PLATFORM_WARNING + 0.6)
	assert_eq(platform.state, DisappearingPlatform.State.SOLID)


# ------------------------------------------------------------- moving platforms

func test_moving_platform_travels_and_returns() -> void:
	var platform: MovingPlatform = _instance("res://scenes/arena/moving_platform.tscn")
	platform.travel = Vector3(0, 0, 4)
	platform.speed = 8.0
	platform.dwell = 0.05
	var origin: Vector3 = platform.global_position

	await wait_seconds(0.8)
	assert_gt(platform.global_position.distance_to(origin), 1.0, "it left the start")
	await wait_seconds(1.4)
	assert_almost_eq(platform.global_position.z, origin.z, 1.0, "and it comes back")


func test_moving_platform_syncs_to_physics_so_riders_are_carried() -> void:
	var platform: MovingPlatform = _instance("res://scenes/arena/moving_platform.tscn")
	assert_true(platform.sync_to_physics,
		"without this the physics server will not carry a CharacterBody3D")


# -------------------------------------------------------------------- zip lines

func test_zip_line_carries_a_rider_to_the_end() -> void:
	var line: ZipLine = _instance("res://scenes/arena/zip_line.tscn")
	var player: Player = _instance("res://scenes/player/player.tscn")
	line.speed = 40.0

	# Arrival has to be measured when the ride ends: after the dismount the rider
	# keeps their exit momentum and is legitimately long gone.
	#
	# The array is not decoration - GDScript lambdas capture by value, so assigning
	# to a plain local inside the callback would never reach this scope.
	var arrival: Array[Vector3] = [Vector3.ZERO]
	line.ride_finished.connect(func() -> void: arrival[0] = player.global_position)

	assert_true(line.try_mount(player), "mounting an empty line works")
	assert_true(line.is_occupied)
	await wait_seconds(1.5)
	assert_false(line.is_occupied, "the ride ends on its own")
	assert_lt(arrival[0].distance_to(line.end_point.global_position), 3.0,
		"the rider arrives")


func test_a_zip_line_takes_one_rider() -> void:
	var line: ZipLine = _instance("res://scenes/arena/zip_line.tscn")
	var player: Player = _instance("res://scenes/player/player.tscn")
	assert_true(line.try_mount(player))
	assert_false(line.try_mount(player), "already occupied")


## A ride that dumps you at zero speed is a punishment for using it.
func test_dismount_keeps_most_of_the_speed() -> void:
	var line: ZipLine = _instance("res://scenes/arena/zip_line.tscn")
	var player: Player = _instance("res://scenes/player/player.tscn")
	line.speed = 20.0
	line.try_mount(player)
	await wait_seconds(1.6)
	assert_gt(player.velocity.length(), line.speed * line.exit_speed_fraction * 0.8,
		"exit momentum is preserved")


## Reported from playtest: standing on a platform above a pool still cost health.
## The trigger volume is a column of air, and being inside the column is not the
## same as standing in the acid.
func test_hazard_does_not_reach_someone_on_a_platform_above_it() -> void:
	var hazard: HazardZone = _instance("res://scenes/arena/hazard_zone.tscn")
	hazard.tick_interval = 0.05

	# A floor 3m up, and a body standing on it directly over the pool.
	var platform := StaticBody3D.new()
	platform.collision_layer = PhysicsLayers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 0.4, 10)
	shape.shape = box
	platform.add_child(shape)
	add_child_autofree(platform)
	platform.global_position = hazard.global_position + Vector3.UP * 3.0

	var target: CharacterBody3D = _make_target()
	target.global_position = hazard.global_position + Vector3.UP * 3.2

	var health: HealthComponent = target.get_child(1)
	await wait_seconds(Tokens.HAZARD_WARNING + 0.4)
	assert_eq(health.current_health, health.max_health,
		"acid on the ground must not reach a floor above it")


func test_hazard_still_reaches_someone_standing_in_it() -> void:
	var hazard: HazardZone = _instance("res://scenes/arena/hazard_zone.tscn")
	hazard.tick_interval = 0.05
	var target: CharacterBody3D = _make_target()
	target.global_position = hazard.global_position

	var health: HealthComponent = target.get_child(1)
	await wait_seconds(Tokens.HAZARD_WARNING + 0.3)
	assert_lt(health.current_health, health.max_health,
		"the fix must not make the pool harmless")
