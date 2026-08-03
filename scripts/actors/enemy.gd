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

	if _stagger_timer > 0.0:
		# Staggered enemies keep their knockback but stop steering.
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
	elif is_moving:
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
	_stagger_timer = 0.0
	_flash_timer = 0.0
	_attack_cooldown_left = 0.0
	_slow_multiplier = 1.0
	_stuck_time = 0.0
	_jump_cooldown_left = 0.0
	_last_position = spawn_position

	_apply_presentation()
	_apply_collision()
	_apply_silhouette_markers()

	if health != null:
		health.max_health = data.max_health
		health.reset()
	if agent != null:
		agent.max_speed = data.move_speed
	_set_hitboxes_enabled(true)
	_rebuild_behavior_tree()

	is_active = true
	AudioPool.play_3d(data.spawn_sound, global_position, AudioPool.BUS_ENEMIES)


func _on_acquired() -> void:
	is_active = false


func _on_released() -> void:
	is_active = false
	is_moving = false
	_set_hitboxes_enabled(false)
	_clear_behavior_tree()


# Public API - used by the AI leaves

func get_player() -> Node3D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Node3D
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
	var player_health: HealthComponent = _find_health(player)
	if player_health != null:
		player_health.apply_damage(data.damage)
	AudioPool.play_3d(data.attack_sound, global_position, AudioPool.BUS_ENEMIES)


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

	_stuck_time += delta
	if _stuck_time < STUCK_TIME or _jump_cooldown_left > 0.0:
		return
	if _try_jump_obstacle():
		_stuck_time = 0.0


## Probes the obstacle the way the player's mantle does: something solid at knee
## height with clear air above it is a thing to jump, not a wall to lean on.
func _try_jump_obstacle() -> bool:
	if data == null or not data.can_jump:
		return false

	var heading: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if heading.length_squared() < 0.01:
		heading = move_target - global_position
		heading.y = 0.0
	if heading.length_squared() < 0.01:
		return false
	heading = heading.normalized()

	var reach: float = data.collision_radius + 0.6
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state

	# Something in the way at knee height...
	var knee: Vector3 = global_position + Vector3.UP * 0.35
	var knee_query := PhysicsRayQueryParameters3D.create(knee, knee + heading * reach,
		PhysicsLayers.WORLD | PhysicsLayers.ENEMY)
	knee_query.exclude = [get_rid()]
	if space.intersect_ray(knee_query).is_empty():
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
	var map: RID = agent.get_navigation_map()
	return map.is_valid() and not NavigationServer3D.map_get_regions(map).is_empty()


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
	_resize_capsule(body_hitbox_shape, maxf(data.collision_height - 0.4, 0.4),
		data.collision_radius, 0.5)

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
	ObjectPool.release(self)


func _find_health(node: Node) -> HealthComponent:
	for child: Node in node.get_children():
		var component := child as HealthComponent
		if component != null:
			return component
	return null
