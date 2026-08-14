class_name Enemy
extends CharacterBody3D
## One enemy scene serves every archetype; `EnemyData` supplies the silhouette,
## stats, audio and behavior tree. Pooled, so `setup()` must fully reset state.
##
## Perception is deliberately absent: enemies always know where the player is
## (CLAUDE.md 5.3). The behavior trees describe engagement, not searching.

signal staggered()

## How long an enemy may be commanded to move while covering no ground before it
## treats itself as obstructed.
const STUCK_TIME: float = 0.3
## Metres per second of real progress below which it is not actually moving.
const STUCK_SPEED: float = 0.9
const JUMP_COOLDOWN: float = 0.9

const STAGGER_TIME: float = 0.18
const FLASH_TIME: float = 0.08
const GRAVITY: float = 24.0

@export var health: HealthComponent
@export var agent: NavigationAgent3D
@export var mesh_instance: MeshInstance3D
@export var body_hitbox: HitboxComponent
@export var head_hitbox: HitboxComponent
@export var body_shape: CollisionShape3D
@export var body_hitbox_shape: CollisionShape3D
@export var head_hitbox_shape: CollisionShape3D
@export var tree_holder: Node
@export var halo: MeshInstance3D
@export var tether: MeshInstance3D
@export var flash_color: Color = Color(1.0, 0.9, 0.75)

var data: EnemyData
var is_active: bool = false
## Set by AI leaves; the enemy walks itself toward this each physics frame.
var move_target: Vector3 = Vector3.ZERO
var is_moving: bool = false

## Identifies this enemy across the network. Assigned by the host on spawn and
## carried in every snapshot, so a client can tell which body a position update
## belongs to. Zero means "not replicated" - the single-player case.
var net_id: int = 0
## True on a client's copy of a host-owned enemy. A remote enemy is a puppet:
## it has no brain, takes no damage locally and never moves itself. Everything
## it does arrives from the host, and simulating any of it here would fight the
## incoming snapshot rather than smooth it.
var is_remote: bool = false
## Peer whose shot last landed on this enemy, and therefore who gets paid when it
## dies. Zero means the host's own player, which is also the single-player answer.
##
## Last hit rather than most damage: it costs one integer instead of a table per
## enemy, and in a horde shooter where the same rusher is being shot by three
## people the last hit is the one that reads as the kill anyway.
var last_damager: int = 0

var _player: Node3D
var _material: StandardMaterial3D
var _flash_timer: float = 0.0
var _stagger_timer: float = 0.0
var _attack_cooldown_left: float = 0.0
var _behavior_tree: Node
var _slow_multiplier: float = 1.0
## Whoever the healer is currently helping, for the tether beam.
var _tether_target: Enemy
var _stuck_time: float = 0.0
var _jump_cooldown_left: float = 0.0
var _last_position: Vector3
## Set while crossing a NavigationLink3D under our own ballistic arc.
var _link_target: Vector3 = Vector3.ZERO
var _is_traversing_link: bool = false
## The arena's jump links, resolved once per spawn. They are placed at author time
## and never change during a run, so paying for a group query every frame - which
## allocates a fresh array each call - buys nothing.
var _links: Array[JumpLink] = []
## Latched answer to _has_navmesh(). NavigationServer3D.map_get_regions()
## allocates a fresh Array[RID] on every call, and _steer() asks the question
## every physics frame for every walking enemy - the same per-frame throwaway
## allocation already removed from _find_link_ahead(). The arena's regions are
## baked offline and committed (see ArenaNavigation), so once the answer is yes
## it stays yes for this spawn.
##
## Only `true` is cached, and the latch is cleared in setup(): a pooled enemy
## outlives the arena it was built in, so caching a `false` from a map that has
## not resolved yet - or from a previous, navmesh-less arena - would leave it
## straight-line steering for its whole life.
var _navmesh_latched: bool = false


func _ready() -> void:
	add_to_group(&"enemy")
	if health != null:
		health.damaged.connect(_on_damaged)
		health.died.connect(_on_died)
	if body_hitbox != null:
		body_hitbox.hit_taken.connect(_on_hit_taken)
	if head_hitbox != null:
		head_hitbox.hit_taken.connect(_on_hit_taken)


func _physics_process(delta: float) -> void:
	if not is_active:
		return

	_flash_timer = maxf(_flash_timer - delta, 0.0)
	if _flash_timer <= 0.0 and _material != null and _material.emission_energy_multiplier > 0.0:
		_material.emission_energy_multiplier = 0.0
	_stagger_timer = maxf(_stagger_timer - delta, 0.0)
	_attack_cooldown_left = maxf(_attack_cooldown_left - delta, 0.0)
	_jump_cooldown_left = maxf(_jump_cooldown_left - delta, 0.0)

	if is_remote:
		# Keep the cosmetics that are purely local - the halo spin and the
		# healer's tether are decoration, not state anyone needs to agree on.
		# Everything below this line is simulation, and on a client it would
		# argue with the host's snapshot instead of following it.
		if halo != null and halo.visible:
			halo.rotate_y(delta * 0.8)
		_update_tether()
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif velocity.y < 0.0:
		# Only cancel downward speed. Zeroing unconditionally would wipe the jump
		# impulse set at the end of the previous frame, since the enemy is still
		# touching the floor when this runs.
		velocity.y = 0.0

	if halo != null and halo.visible:
		# The ring reads as a marker, not as part of the body, so it turns on its
		# own axis rather than following the enemy's facing.
		halo.rotate_y(delta * 0.8)
	_update_tether()

	if _is_traversing_link:
		# Mid-arc: steering would fight the ballistic solution and land it short.
		_tick_link_traversal()
	elif _stagger_timer > 0.0:
		# Staggered enemies keep their knockback but stop steering.
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
	elif is_moving:
		# Checked every frame while walking, not only once wedged against something.
		# A link that leads *down* has no wall to stop the enemy first, so gating
		# traversal behind being stuck meant those were never taken at all.
		if not _try_traverse_link():
			_steer(delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)

	move_and_slide()
	_check_obstruction(delta)


# Public API - lifecycle

## Configures the enemy for an archetype. Called every time it leaves the pool.
func setup(enemy_data: EnemyData, spawn_position: Vector3) -> void:
	data = enemy_data
	global_position = spawn_position
	velocity = Vector3.ZERO
	is_moving = false
	move_target = spawn_position
	# Pooled: an enemy carries the previous occupant's bounty claim otherwise.
	last_damager = 0
	_stagger_timer = 0.0
	_flash_timer = 0.0
	_attack_cooldown_left = 0.0
	_slow_multiplier = 1.0
	_stuck_time = 0.0
	_jump_cooldown_left = 0.0
	_last_position = spawn_position
	_is_traversing_link = false
	_link_target = spawn_position
	_navmesh_latched = false
	_cache_links()

	_apply_presentation()
	_apply_collision()
	_apply_silhouette_markers()

	if health != null:
		health.max_health = data.max_health
		health.reset()
	if agent != null:
		agent.max_speed = data.move_speed
	# A puppet keeps its hitboxes so local shots still register a hit to report
	# to the host, but it is never given a brain - the host owns every decision
	# this enemy makes, and a second tree running here would pick different ones.
	_set_hitboxes_enabled(true)
	if not is_remote:
		_rebuild_behavior_tree()

	is_active = true
	AudioPool.play_3d(data.spawn_sound, global_position, AudioPool.BUS_ENEMIES)


## Client-side exit: the host has decided this enemy is gone.
##
## Plays the same death beat a real kill does but claims none of its
## consequences. The reward and the wave's remaining count belong to the host's
## simulation; emitting enemy_killed here would pay every client its own copy of
## the bounty and let four machines disagree about when the wave is clear.
func despawn_remote() -> void:
	if not is_active:
		return
	is_active = false
	is_moving = false
	_set_hitboxes_enabled(false)
	_clear_behavior_tree()
	if data != null:
		AudioPool.play_3d(data.death_sound, global_position, AudioPool.BUS_ENEMIES)
	ObjectPool.release(self)


func _on_acquired() -> void:
	is_active = false


func _on_released() -> void:
	is_active = false
	is_moving = false
	_set_hitboxes_enabled(false)
	_clear_behavior_tree()


# Public API - used by the AI leaves

## The player this enemy is fighting. Re-targets only when the current one dies
## or leaves, never on distance alone: the AI is aggro-locked by design (see
## MovementComponent's note on why player speed is safe), and picking the
## closest player every frame would make enemies flip between two teammates
## running past each other instead of committing to one.
func get_player() -> Node3D:
	if _player == null or not Players.is_alive(_player):
		_player = Players.nearest(global_position)
	return _player


func get_player_position() -> Vector3:
	var player: Node3D = get_player()
	return player.global_position if player != null else global_position


func get_distance_to_player() -> float:
	var player: Node3D = get_player()
	if player == null:
		return INF
	return global_position.distance_to(player.global_position)


func set_move_target(target: Vector3) -> void:
	move_target = target
	is_moving = true
	if agent != null:
		agent.target_position = target


func stop_moving() -> void:
	is_moving = false


## Yaw-only turn toward the player; enemies never pitch.
func face_player(delta: float, turn_speed: float = 8.0) -> void:
	var to_player: Vector3 = get_player_position() - global_position
	to_player.y = 0.0
	if to_player.length_squared() < 0.01:
		return
	var target_yaw: float = atan2(to_player.x, to_player.z)
	rotation.y = rotate_toward(rotation.y, target_yaw, turn_speed * delta)


func is_attack_ready() -> bool:
	return _attack_cooldown_left <= 0.0


func start_attack_cooldown() -> void:
	_attack_cooldown_left = data.attack_cooldown if data != null else 1.0


func is_staggered() -> bool:
	return _stagger_timer > 0.0


## Stun grenade. Reuses the stagger timer, so a stunned enemy also fails its
## behavior tree's attack branch rather than merely standing still.
func apply_stun(duration: float) -> void:
	_stagger_timer = maxf(_stagger_timer, duration)
	staggered.emit()


## Slow field. Multiplier is re-applied every frame the enemy is inside, and
## cleared when it leaves or the field expires.
func apply_slow(multiplier: float) -> void:
	_slow_multiplier = clampf(multiplier, 0.05, 1.0)


func clear_slow() -> void:
	_slow_multiplier = 1.0


## Radius of the shootable volume. Falls back to the body capsule when the archetype
## has not declared one, which is correct for anything roughly as wide as it is deep.
func get_hitbox_radius() -> float:
	if data == null:
		return 0.4
	return data.hitbox_radius if data.hitbox_radius > 0.0 else data.collision_radius


func get_move_speed() -> float:
	var speed: float = data.move_speed if data != null else 5.0
	return speed * _slow_multiplier


## Melee hit on the player, applied only if they are still in range.
func deal_melee_damage() -> void:
	var player: Node3D = get_player()
	if player == null or data == null:
		return
	if global_position.distance_to(player.global_position) > data.attack_range * 1.4:
		return  # The player escaped the wind-up. That is the point of telegraphing.
	if not _can_see(player):
		# Distance alone is not reach. An enemy wedged under a platform is within
		# 3m of someone standing on top of it, and would otherwise punch through
		# the floor - damage from nowhere, with nothing on screen to explain it.
		return
	var player_health: HealthComponent = _find_health(player)
	if player_health != null:
		player_health.apply_damage(data.damage)
	AudioPool.play_3d(data.attack_sound, global_position, AudioPool.BUS_ENEMIES)


## Clear line from this enemy's head to the target's chest.
##
## Note this is NOT perception - enemies still always know where the player is
## (CLAUDE.md 5.3). It only stops an attack landing through solid geometry.
func _can_see(target: Node3D) -> bool:
	var from: Vector3 = global_position + Vector3.UP * data.head_offset
	var to: Vector3 = target.global_position + Vector3.UP * 1.0
	var query := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.WORLD)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func fire_projectile() -> void:
	if data == null or data.projectile_scene == null:
		return
	var origin: Vector3 = global_position + Vector3.UP * data.head_offset
	var target: Vector3 = get_player_position() + Vector3.UP * 1.0
	var projectile: Node = ObjectPool.acquire(data.projectile_scene)
	var typed := projectile as EnemyProjectile
	if typed == null:
		push_error("Enemy: %s projectile_scene is not an EnemyProjectile" % data.id)
		return
	typed.launch(origin, (target - origin).normalized(), data.damage, data.projectile_speed, self)
	AudioPool.play_3d(data.attack_sound, global_position, AudioPool.BUS_ENEMIES)


## Heals every other living enemy inside `heal_radius`. Returns how many it helped,
## so the healer's tree can fail when there is nothing to do.
func heal_nearby_allies() -> int:
	if data == null:
		return 0
	var healed: int = 0
	for node: Node in get_tree().get_nodes_in_group(&"enemy"):
		var other := node as Enemy
		if other == null or other == self or not other.is_active or other.health == null:
			continue
		if global_position.distance_to(other.global_position) > data.heal_radius:
			continue
		if other.health.current_health >= other.health.max_health:
			continue
		other.health.heal(data.heal_amount)
		if _tether_target == null or not is_instance_valid(_tether_target) 				or other.health.get_health_fraction() < _tether_target.health.get_health_fraction():
			_tether_target = other
		healed += 1
	return healed


## Plays the visual half of a wind-up telegraph.
func show_windup(progress: float) -> void:
	if _material == null:
		return
	_material.emission_energy_multiplier = progress * 2.5


func clear_windup() -> void:
	if _material != null and _flash_timer <= 0.0:
		_material.emission_energy_multiplier = 0.0


# Private

## Steers along the navmesh when there is one, and straight at the target when there
## is not.
##
## The distinction matters. Straight-line steering is correct for flying variants
## and for a map with no navmesh at all (CLAUDE.md 5.3), but it is wrong when a
## navmesh exists and the target simply cannot be walked to: charging the straight
## line then grinds the enemy into whatever wall is in the way, which is what
## "enemies get stuck beside the ramp" looks like from the outside.
##
## So when the path runs out short of an unreachable target, the enemy stops at the
## closest reachable point instead of pushing into geometry.
func _steer(delta: float) -> void:
	var next_point: Vector3 = move_target

	if agent != null and _has_navmesh():
		if not agent.is_navigation_finished():
			var path_point: Vector3 = agent.get_next_path_position()
			if path_point.distance_squared_to(global_position) > 0.01:
				next_point = path_point
		elif not agent.is_target_reachable():
			# As close as walking gets. Stop rather than shove.
			_stop_horizontal(delta)
			return

	var direction: Vector3 = next_point - global_position
	direction.y = 0.0
	if direction.length_squared() < 0.04:
		_stop_horizontal(delta)
		return
	direction = direction.normalized()
	var speed: float = get_move_speed()
	velocity.x = move_toward(velocity.x, direction.x * speed, 30.0 * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, 30.0 * delta)


## Watches for the enemy being told to move while covering no ground, and hops the
## thing in the way.
##
## Deliberately reactive rather than predictive: it does not care *why* it is stuck
## - a ramp lip, a crowded doorway, a navmesh seam, another enemy - only that it is.
## That is what makes it a safety net for every future layout rather than a patch
## for the one ramp that was reported.
func _check_obstruction(delta: float) -> void:
	var travelled: float = Vector2(global_position.x - _last_position.x,
		global_position.z - _last_position.z).length()
	_last_position = global_position

	var wants_to_move: bool = is_moving and not is_staggered()
	var making_progress: bool = travelled / maxf(delta, 0.0001) > STUCK_SPEED
	if not wants_to_move or making_progress or not is_on_floor():
		_stuck_time = 0.0
		return

	# A ledge is far commoner than a real obstacle, and stepping is instant, so try
	# it every frame rather than waiting out the stuck timer.
	if _try_step_up():
		_stuck_time = 0.0
		return

	_stuck_time += delta
	if _stuck_time < STUCK_TIME or _jump_cooldown_left > 0.0:
		return
	if _try_jump_obstacle():
		_stuck_time = 0.0


## Rides out a link crossing. The arc was solved at launch, so nothing steers here -
## the traversal simply ends when the enemy is back on the ground.
func _tick_link_traversal() -> void:
	if is_on_floor() and velocity.y <= 0.0:
		_is_traversing_link = false
		# Land facing the way it was going, so the walk resumes without a pivot.
		set_move_target(_link_target)
		return
	# Bail out if the arc was interrupted - a wall, a wave reset, anything.
	if global_position.y < _link_target.y - 12.0:
		_is_traversing_link = false


## Crosses a NavigationLink3D by jumping it.
##
## The pathfinder will happily route through a link, but it only ever hands back a
## point to walk to - so without this the enemy walks to the lip of the gap and
## stands there. The link supplies the arc; the enemy just commits to it.
func _try_traverse_link() -> bool:
	if data == null or not data.can_jump or _is_traversing_link:
		return false
	# Nothing launches off the ground it is not standing on, and the cooldown is what
	# stops an enemy that lands beside a link's far end from immediately taking it
	# back - now that this runs every frame rather than only when wedged.
	if not is_on_floor() or _jump_cooldown_left > 0.0:
		return false

	# One scan answers both questions. This used to ask "is a link the next step?"
	# and "which link is it?" separately, walking the whole link group twice - and
	# the first question was answered by looking for exactly the link the second one
	# then went and found again, so it could never actually reject anything.
	var link: JumpLink = _find_link_ahead()
	if link == null:
		return false

	var exit: Vector3 = link.get_exit_for(global_position)
	velocity = link.get_launch_velocity(global_position, exit, GRAVITY)
	_link_target = exit
	_is_traversing_link = true
	_jump_cooldown_left = JUMP_COOLDOWN
	return true


## Resolved on spawn rather than in _ready(): a pooled enemy is built once but reused
## across waves and arenas, so the links it should know about are the ones present
## the moment it is put into play.
func _cache_links() -> void:
	_links.clear()
	for node: Node in get_tree().get_nodes_in_group(&"jump_link"):
		var link := node as JumpLink
		if link != null:
			_links.push_back(link)


## The nearest link whose near end we are standing on, and whose far end is closer to
## where we are trying to go than we are now - otherwise jumping is a detour.
##
## Reads the cached list rather than the scene tree. This runs every frame for every
## walking enemy now, and a group query allocates its result array on each call - at
## a full wave that was well over a thousand throwaway arrays a second, for a set of
## links that never changes during a run.
func _find_link_ahead() -> JumpLink:
	var best: JumpLink = null
	var best_distance: float = INF
	for link: JumpLink in _links:
		if not is_instance_valid(link) or not link.enabled:
			continue
		var distance: float = global_position.distance_to(_nearest_end(link))
		if distance > data.collision_radius + 1.6 or distance >= best_distance:
			continue
		var exit: Vector3 = link.get_exit_for(global_position)
		if exit.distance_to(move_target) >= global_position.distance_to(move_target):
			continue  # the far side is no closer to the goal, so jumping is a detour
		best = link
		best_distance = distance
	return best


func _nearest_end(link: JumpLink) -> Vector3:
	var start: Vector3 = link.get_start_global()
	var end: Vector3 = link.get_end_global()
	return start if global_position.distance_squared_to(start) \
		< global_position.distance_squared_to(end) else end


## Lifts the enemy over a low ledge - the ramp's own side edge, a platform lip, the
## seam where two boxes meet.
##
## This is the case the reported bug actually was: head-on the ramp is a slope and
## move_and_slide climbs it; from the side it is a vertical edge, and an edge of any
## height stops a CharacterBody3D dead. The navmesh routes across those edges
## because the bake believes the agent can climb agent_max_climb, so the body has to
## be able to as well or the two disagree and the enemy grinds.
func _try_step_up() -> bool:
	if data == null or not is_on_wall():
		return false
	var step_height: float = data.max_auto_step
	if step_height <= 0.0:
		return false

	var heading: Vector3 = _desired_heading()
	if heading == Vector3.ZERO:
		return false

	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var reach: float = data.collision_radius + 0.35
	var ahead: Vector3 = global_position + heading * reach

	# Nothing to step onto if the space above the ledge is occupied.
	var head_room: Vector3 = global_position + Vector3.UP * (step_height + 0.1)
	var head_query := PhysicsRayQueryParameters3D.create(head_room,
		head_room + heading * reach, PhysicsLayers.WORLD)
	head_query.exclude = [get_rid()]
	if not space.intersect_ray(head_query).is_empty():
		return false

	# Find the top of whatever is in front, by looking down from above it.
	var from_above: Vector3 = ahead + Vector3.UP * (step_height + 0.1)
	var down_query := PhysicsRayQueryParameters3D.create(from_above,
		ahead - Vector3.UP * 0.05, PhysicsLayers.WORLD)
	down_query.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(down_query)
	if hit.is_empty():
		return false

	var rise: float = float(hit["position"].y) - global_position.y
	if rise <= 0.02 or rise > step_height:
		return false

	# Lifting the body without checking it fits is what makes an enemy bounce: the
	# next depenetration shoves it back out and it re-approaches, forever. Test the
	# destination first, and commit only if it can also move forward from there -
	# otherwise standing on the very lip would just stall it again.
	var lifted: Transform3D = global_transform
	lifted.origin.y = float(hit["position"].y) + 0.05
	var nudge: Vector3 = heading * (data.collision_radius * 0.5)
	if test_move(lifted, nudge):
		return false

	global_position = lifted.origin + nudge
	return true


## Where the enemy is trying to go, preferring its actual motion and falling back to
## its target when a wall has already scrubbed the velocity to nothing.
func _desired_heading() -> Vector3:
	var heading := Vector3(velocity.x, 0.0, velocity.z)
	if heading.length_squared() < 0.01:
		heading = move_target - global_position
		heading.y = 0.0
	if heading.length_squared() < 0.01:
		return Vector3.ZERO
	return heading.normalized()


## Probes the obstacle the way the player's mantle does: something solid at knee
## height with clear air above it is a thing to jump, not a wall to lean on.
func _try_jump_obstacle() -> bool:
	if data == null or not data.can_jump:
		return false

	var heading: Vector3 = _desired_heading()
	if heading == Vector3.ZERO:
		return false

	var reach: float = data.collision_radius + 0.6
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state

	# Something in the way just above the feet. Probing at knee height would sail
	# over exactly the low edges that cause the most trouble.
	var shin: Vector3 = global_position + Vector3.UP * 0.12
	var shin_query := PhysicsRayQueryParameters3D.create(shin, shin + heading * reach,
		PhysicsLayers.WORLD | PhysicsLayers.ENEMY)
	shin_query.exclude = [get_rid()]
	if space.intersect_ray(shin_query).is_empty():
		return false

	# ...and nothing above it, or the jump would just be a shorter grind.
	var clearance: Vector3 = global_position + Vector3.UP * data.max_step_height
	var clear_query := PhysicsRayQueryParameters3D.create(clearance,
		clearance + heading * reach, PhysicsLayers.WORLD)
	if not space.intersect_ray(clear_query).is_empty():
		return false

	velocity.y = data.jump_velocity
	_jump_cooldown_left = JUMP_COOLDOWN
	return true


## True when there is baked navigation to follow. False means straight-line
## steering is the right answer, not a fallback for a broken path.
func _has_navmesh() -> bool:
	if _navmesh_latched:
		return true
	var map: RID = agent.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_regions(map).is_empty():
		return false
	_navmesh_latched = true
	return true


func _stop_horizontal(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)


func _apply_presentation() -> void:
	if mesh_instance == null:
		return
	if data.mesh != null:
		mesh_instance.mesh = data.mesh
	mesh_instance.scale = Vector3.ONE * data.body_scale
	if _material == null:
		_material = StandardMaterial3D.new()
		mesh_instance.material_override = _material
	_material.albedo_color = data.body_color
	_material.emission_enabled = true
	_material.emission = flash_color
	_material.emission_energy_multiplier = 0.0


## Shapes are resized per archetype, so each pooled instance needs its own copy -
## sub-resources in a .tscn are shared between instances by default.
## The halo and the tether are what make the Healer readable; every other archetype
## turns them off.
func _apply_silhouette_markers() -> void:
	if halo != null:
		halo.visible = data.has_halo
		if data.has_halo:
			halo.position.y = data.halo_height
			halo.scale = Vector3.ONE * data.halo_radius
			_tint(halo, data.body_color)
	if tether != null:
		tether.visible = false
		_tint(tether, data.body_color)
	_tether_target = null


func _tint(mesh: MeshInstance3D, tint: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 1.4
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = material


## Beam from the healer to its target, redrawn each frame it is active. Breaking
## line of sight is not simulated: the tether simply follows whoever is being healed.
func _update_tether() -> void:
	if tether == null or not data.has_tether:
		return
	if _tether_target == null or not is_instance_valid(_tether_target) 			or not _tether_target.is_active:
		tether.visible = false
		return
	var to_target: Vector3 = _tether_target.global_position - global_position
	var length: float = to_target.length()
	if length < 0.1:
		tether.visible = false
		return
	tether.visible = true
	tether.global_position = global_position + Vector3.UP * data.head_offset * 0.8
	tether.look_at(_tether_target.global_position + Vector3.UP, Vector3.UP)
	tether.scale = Vector3(1.0, 1.0, length)


func _apply_collision() -> void:
	_resize_capsule(body_shape, data.collision_height, data.collision_radius, 0.5)
	# The hitbox tracks the silhouette, the body capsule tracks the navmesh - see
	# EnemyData.hitbox_radius for why those stopped being the same number.
	_resize_capsule(body_hitbox_shape, maxf(data.collision_height - 0.4, 0.4),
		get_hitbox_radius(), 0.5)

	if head_hitbox_shape == null:
		return
	if not _is_owned_shape(head_hitbox_shape):
		head_hitbox_shape.shape = head_hitbox_shape.shape.duplicate()
	var head_sphere := head_hitbox_shape.shape as SphereShape3D
	if head_sphere != null:
		head_sphere.radius = data.head_radius
		head_hitbox_shape.position.y = data.head_offset


func _resize_capsule(node: CollisionShape3D, height: float, radius: float,
		center_fraction: float) -> void:
	if node == null:
		return
	if not _is_owned_shape(node):
		node.shape = node.shape.duplicate()
	var capsule := node.shape as CapsuleShape3D
	if capsule == null:
		return
	capsule.radius = radius
	capsule.height = maxf(height, radius * 2.0)
	node.position.y = capsule.height * center_fraction


func _is_owned_shape(node: CollisionShape3D) -> bool:
	return node.shape != null and node.shape.resource_local_to_scene


func _rebuild_behavior_tree() -> void:
	_clear_behavior_tree()
	if data.behavior_tree == null or tree_holder == null:
		return
	_behavior_tree = data.behavior_tree.instantiate()
	tree_holder.add_child(_behavior_tree)
	var beehave := _behavior_tree as BeehaveTree
	if beehave != null:
		beehave.actor = self


func _clear_behavior_tree() -> void:
	if _behavior_tree != null and is_instance_valid(_behavior_tree):
		_behavior_tree.queue_free()
	_behavior_tree = null


func _set_hitboxes_enabled(enabled: bool) -> void:
	# Hitboxes are found by the projectile's ray, not by monitoring, so they have
	# to leave their physics layer rather than just stop processing.
	for hitbox: HitboxComponent in [body_hitbox, head_hitbox]:
		if hitbox != null:
			hitbox.collision_layer = PhysicsLayers.HITBOX if enabled else 0


func _on_hit_taken(_amount: float, _is_headshot: bool, hit_position: Vector3) -> void:
	# Visible reaction to every hit is a gunplay-feel requirement (CLAUDE.md 5.3).
	_flash_timer = FLASH_TIME
	if _material != null:
		_material.emission_energy_multiplier = 3.0
	var resistance: float = clampf(data.stagger_resistance if data != null else 0.0, 0.0, 1.0)
	if resistance >= 1.0:
		return
	_stagger_timer = STAGGER_TIME * (1.0 - resistance)
	var knockback: Vector3 = global_position - hit_position
	knockback.y = 0.0
	if knockback.length_squared() > 0.001:
		var force: float = 4.0 * (1.0 - resistance) / maxf(data.mass if data != null else 1.0, 0.1)
		velocity += knockback.normalized() * force
	staggered.emit()


func _on_damaged(_amount: float, _remaining: float) -> void:
	pass


func _on_died() -> void:
	if not is_active:
		return
	is_active = false
	is_moving = false
	_set_hitboxes_enabled(false)
	_clear_behavior_tree()
	AudioPool.play_3d(data.death_sound, global_position, AudioPool.BUS_ENEMIES)
	EventBus.enemy_killed.emit(data.id, global_position, data.reward_currency)
	# The bounty goes to whoever was shooting, which is not always the machine
	# resolving the death. EnemyReplicator sends it on when that is a client;
	# with no session, or with the host's own player on the trigger, it is paid
	# here and the single-player path is unchanged.
	if EnemyReplicator.instance != null and EnemyReplicator.instance.credit_kill(
			last_damager, data.id, global_position, data.reward_currency):
		ObjectPool.release(self)
		return
	EventBus.kill_credited.emit(data.reward_currency)
	ObjectPool.release(self)


func _find_health(node: Node) -> HealthComponent:
	for child: Node in node.get_children():
		var component := child as HealthComponent
		if component != null:
			return component
	return null
