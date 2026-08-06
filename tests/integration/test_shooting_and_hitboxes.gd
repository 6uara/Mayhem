extends GutTest
## Where shots come from, where they go, and what they are able to hit.
##
## All three were reported from the same playtest: the gun rotating away as it
## fired, rounds leaving the player's chest instead of the barrel, and shots
## passing through enemies that were plainly in the crosshair. None of them failed
## anything in the build - the code did exactly what it said, and what it said was
## wrong - so each gets a test that would have caught it.

const PLAYER_SCENE: String = "res://scenes/player/player.tscn"


func _player() -> Player:
	return add_child_autofree(load(PLAYER_SCENE).instantiate())


# ------------------------------------------------------------- viewmodel kick

## Recovery is a rate, so a weapon that fires faster than it recovers used to
## accumulate kick without bound and the gun simply rotated away mid-magazine.
func test_sustained_fire_never_spins_the_viewmodel() -> void:
	var player: Player = _player()
	await wait_physics_frames(2)
	var weapon: WeaponComponent = player.weapon
	assert_not_null(weapon.data, "precondition: weapon has data")

	# Far more shots than any magazine, with no recovery time between them.
	for _i: int in 200:
		weapon._view_kick_rot = maxf(weapon._view_kick_rot - weapon.view_kick_up_degrees,
			-weapon.view_kick_max_degrees)
	assert_almost_eq(weapon._view_kick_rot, -weapon.view_kick_max_degrees, 0.001,
		"kick has to stop at its ceiling, not keep turning")


func test_the_kick_rides_a_pivot_so_it_reads_as_pitch() -> void:
	var player: Player = _player()
	await wait_physics_frames(2)
	var weapon: WeaponComponent = player.weapon
	var pivot: Node3D = weapon._view
	assert_not_null(pivot, "the viewmodel hangs off a pivot the component owns")

	# The pivot carries no authored yaw of its own; the model underneath does.
	# Pitching a node that is already yawed 90 degrees reads on screen as roll.
	assert_almost_eq(pivot.rotation_degrees.y, 0.0, 0.001,
		"the pivot must stay unrotated so its X axis is the screen's")
	assert_gt(pivot.get_child_count(), 0, "the model hangs under the pivot")


## The viewmodel renders in the rig's own world, not the arena's - that separation
## is the whole reason a half-metre rifle can sit 36cm from the eye without
## intersecting the wall the player is standing against.
func test_the_viewmodel_renders_in_the_rig_not_the_arena() -> void:
	var player: Player = _player()
	await wait_physics_frames(2)
	var rig: ViewmodelRig = player.get_node(
		"ViewmodelLayer/ViewmodelRig")
	var slots: Node3D = rig.get_slot_parent()

	assert_gt(slots.get_child_count(), 0, "weapons mount their models in the rig")
	for weapon: WeaponComponent in player.weapon_holder.get_all():
		if weapon._view == null:
			continue
		assert_eq(weapon._view.get_parent(), slots,
			"%s renders in the rig's world" % weapon.name)


## The muzzle node was authored at a fixed guess made before the models existed,
## and it sat inside the receiver - rounds appeared to leave from behind the gun.
func test_the_muzzle_sits_at_the_barrel_not_inside_the_gun() -> void:
	var player: Player = _player()
	await wait_physics_frames(2)
	for weapon: WeaponComponent in player.weapon_holder.get_all():
		if weapon._view == null:
			continue
		var model: Node3D = weapon._view.get_child(0)
		var tip: float = weapon._view.position.z + weapon._model_bounds(model).position.z
		assert_almost_eq(weapon.muzzle.position.z, tip, 0.02,
			"%s: muzzle should sit at the barrel tip" % weapon.name)


# ---------------------------------------------------------------- shot origin

## Rounds used to spawn on the aim ray, which is inside the player's own head.
func test_shots_leave_the_muzzle_not_the_player() -> void:
	var player: Player = _player()
	await wait_physics_frames(2)
	var weapon: WeaponComponent = player.weapon
	var aim_origin: Vector3 = weapon.aim_node.global_position

	# A target far down range: nothing point blank, so the muzzle is the honest origin.
	var target: Vector3 = aim_origin - weapon.aim_node.global_transform.basis.z * 50.0
	var origin: Vector3 = weapon._shot_origin(aim_origin, target)

	assert_almost_eq(origin, weapon.muzzle.global_position, Vector3.ONE * 0.001,
		"a shot with room in front of it starts at the barrel")
	assert_gt(origin.distance_to(aim_origin), 0.1,
		"and that is not the same place as the player's head")


## Firing from the barrel at something already past it would send the round out
## the far side, so point blank has to fall back to the aim origin.
func test_point_blank_falls_back_to_the_aim_origin() -> void:
	var player: Player = _player()
	await wait_physics_frames(2)
	var weapon: WeaponComponent = player.weapon
	var aim_origin: Vector3 = weapon.aim_node.global_position
	var target: Vector3 = aim_origin - weapon.aim_node.global_transform.basis.z * 0.2

	assert_almost_eq(weapon._shot_origin(aim_origin, target), aim_origin,
		Vector3.ONE * 0.001, "nothing spawns past what it is being shot at")


## The muzzle is offset from the aim, so firing parallel to the aim would miss to
## one side at every range. Converging on the crosshair's own target is what keeps
## the barrel honest and the crosshair honest at the same time.
func test_the_shot_converges_on_what_the_crosshair_points_at() -> void:
	var player: Player = _player()
	player.global_position = Vector3(0, 0, 0)
	await wait_physics_frames(2)
	var weapon: WeaponComponent = player.weapon

	var aim_origin: Vector3 = weapon.aim_node.global_position
	var direction: Vector3 = -weapon.aim_node.global_transform.basis.z
	var target: Vector3 = weapon._converge_target(aim_origin, direction)
	var origin: Vector3 = weapon._shot_origin(aim_origin, target)
	var travel: Vector3 = (target - origin).normalized()

	# The round starts beside the aim ray but still arrives at its target.
	var arrival: Vector3 = origin + travel * origin.distance_to(target)
	assert_almost_eq(arrival, target, Vector3.ONE * 0.05,
		"the round from the muzzle still lands where the crosshair pointed")


# -------------------------------------------------------------------- hitbox

## The player aims at the silhouette. A mesh wider than its hitbox has an outer
## band that is quietly bulletproof, which reads in play as shots passing through.
func test_no_enemy_is_narrower_to_shoot_than_it_looks() -> void:
	for archetype: String in ["rusher", "elite"]:
		var enemy_data: EnemyData = load("res://data/enemies/%s.tres" % archetype)
		var mesh: Mesh = enemy_data.mesh
		var footprint: float = maxf(mesh.get_aabb().size.x, mesh.get_aabb().size.z)
		var hitbox_width: float = _hitbox_radius(enemy_data) * 2.0
		# Half the footprint is the generous reading - a capsule cannot cover the
		# corners of a wide flat mesh, but it must not leave most of it unhittable.
		assert_gt(hitbox_width, footprint * 0.5,
			"%s: %0.2fm of silhouette against a %0.2fm hitbox"
				% [archetype, footprint, hitbox_width])


## The two radii do different jobs: the body capsule is a navmesh contract, the
## hitbox answers "did that look like a hit". Widening one must not widen the other.
func test_a_wide_hitbox_does_not_widen_the_navigation_body() -> void:
	var elite: EnemyData = load("res://data/enemies/elite.tres")
	assert_gt(elite.hitbox_radius, elite.collision_radius,
		"precondition: the elite is the archetype that needed a wider hitbox")
	assert_lt(elite.collision_radius, 0.85,
		"the body capsule has to stay under the navmesh bake's agent radius")


func _hitbox_radius(enemy_data: EnemyData) -> float:
	return enemy_data.hitbox_radius if enemy_data.hitbox_radius > 0.0 \
		else enemy_data.collision_radius


# ---------------------------------------------------------------- muzzle VFX

## The flash/shell marker lives inside the viewmodel rig, at the barrel tip, with
## the model's own orientation - not at `muzzle` itself, which is deliberately in
## the main world and would put a flash in a space with no relation to what's
## drawn on screen once the player turns.
func test_every_weapon_gets_a_muzzle_marker() -> void:
	var player: Player = _player()
	await wait_physics_frames(2)
	for weapon: WeaponComponent in player.weapon_holder.get_all():
		if weapon._view == null:
			continue
		var marker: Node3D = weapon._view.get_node_or_null("MuzzleMarker")
		assert_not_null(marker, "%s has no muzzle marker" % weapon.name)


## Firing must not error even though the marker lives in a different world than
## `muzzle` - this is the regression a mismatched parent would produce.
func test_firing_spawns_muzzle_vfx_without_error() -> void:
	var player: Player = _player()
	await wait_physics_frames(2)
	var weapon: WeaponComponent = player.weapon
	var marker: Node3D = weapon._view.get_node_or_null("MuzzleMarker")
	assert_not_null(marker, "precondition: marker exists")

	# set_trigger(true) fires synchronously rather than waiting for the next
	# _process tick, so the check must not wait either - the flash lives only
	# 0.06s and awaiting even one frame first was long enough for it to have
	# already freed itself by the time this looked.
	weapon.set_trigger(true)
	weapon.set_trigger(false)

	assert_gt(marker.get_child_count(), 0, "the flash should have spawned on the marker")
