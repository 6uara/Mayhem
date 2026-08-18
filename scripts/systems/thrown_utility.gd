class_name ThrownUtility
extends Node3D
## Base for the three thrown utilities. Handles the arc, the landing and the pooled
## lifetime; subclasses implement what happens when it goes off.
##
## Stepped like projectiles rather than simulated as a RigidBody3D - same reasoning
## (CLAUDE.md 5.1) and it keeps the throw predictable enough to aim.

const GRAVITY: float = 18.0
## Safety net so a utility thrown off the map still returns to the pool.
const MAX_FLIGHT_TIME: float = 6.0

@export var data: UtilityData
@export var bounce_damping: float = 0.35
## Seconds between landing and going off. 0 detonates on contact.
@export var fuse_time: float = 0.0
@export var activate_sound: AudioStream

var _velocity: Vector3 = Vector3.ZERO
var _flight_time: float = 0.0
var _fuse_left: float = 0.0
var _has_landed: bool = false
var _is_active: bool = false
var _thrower: Node = null
## A copy flying for the eyes of one machine. It arcs, lands, goes off and looks
## exactly like the real one; it changes nothing about the enemies, because the
## host is flying its own copy of the same throw and that one is the throw.
##
## Without this a client's grenade did nothing at all: it stunned the puppets in
## front of it, which are scenery, while the real enemies on the host kept
## coming. Utilities are the answer to being surrounded, so "does nothing" is
## the difference between a teammate and a spectator.
var is_cosmetic: bool = false
## Names this throw. Every machine's copy of the same throw carries the same
## number, which is how a landing correction from the host finds the right one.
var throw_id: int = 0
## The component that threw this, and the node the correction travels on. Only
## the utilities that need to agree on where they stopped ever use it.
var thrower_utility: Node = null


func _physics_process(delta: float) -> void:
	if not _is_active:
		return

	if _has_landed:
		_fuse_left -= delta
		if _fuse_left <= 0.0:
			_detonate()
		return

	_flight_time += delta
	if _flight_time >= MAX_FLIGHT_TIME:
		_detonate()
		return

	_velocity.y -= GRAVITY * delta
	var from: Vector3 = global_position
	var to: Vector3 = from + _velocity * delta
	var query := PhysicsRayQueryParameters3D.create(from, to,
		PhysicsLayers.WORLD | PhysicsLayers.ENEMY)
	if _thrower != null and _thrower is CollisionObject3D:
		query.exclude = [(_thrower as CollisionObject3D).get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)

	if hit.is_empty():
		global_position = to
		return

	global_position = hit["position"] + (hit["normal"] as Vector3) * 0.1
	if fuse_time <= 0.0:
		_detonate()
		return
	_land(hit["normal"])


# Public API

func launch(from: Vector3, direction: Vector3, thrower: Node) -> void:
	global_position = from
	_thrower = thrower
	_velocity = direction * (data.throw_force if data != null else 14.0)
	_flight_time = 0.0
	_fuse_left = fuse_time
	_has_landed = false
	_is_active = true
	visible = true


func _on_acquired() -> void:
	_is_active = false
	_has_landed = false


func _on_released() -> void:
	_is_active = false
	_velocity = Vector3.ZERO
	_thrower = null
	thrower_utility = null
	# Pooled: the next throw out of this slot is somebody's real one.
	is_cosmetic = false
	throw_id = 0


## Moves a copy onto the spot the host's own throw came to rest on. Base class
## does nothing with it: a utility only needs this if standing in a slightly
## different place would change the game, which is the wall and nothing else.
func snap_to_landing(_position: Vector3, _yaw: float) -> void:
	pass


# Overridden by subclasses

## Called when the utility goes off. Subclasses do their thing here and are
## responsible for returning themselves to the pool when finished.
func _activate() -> void:
	ObjectPool.release(self)


# Private

func _land(normal: Vector3) -> void:
	_has_landed = true
	_velocity = _velocity.bounce(normal) * bounce_damping
	_fuse_left = fuse_time


func _detonate() -> void:
	_is_active = false
	AudioPool.play_3d(activate_sound, global_position, AudioPool.BUS_WORLD)
	_activate()


## Shared helper: every enemy inside `radius`, closest first.
##
## Empty for a cosmetic copy, which is what keeps every effect in the subclasses
## harmless without any of them having to know they are a copy.
func _enemies_in_radius(radius: float) -> Array[Enemy]:
	var result: Array[Enemy] = []
	if is_cosmetic:
		return result
	for node: Node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := node as Enemy
		if enemy != null and enemy.is_active \
				and global_position.distance_to(enemy.global_position) <= radius:
			result.push_back(enemy)
	return result
