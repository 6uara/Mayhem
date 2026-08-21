class_name ThrownUtility
extends Node3D
## Base for anything thrown on an arc. Handles the arc, the landing and the pooled
## lifetime; subclasses implement what happens when it goes off.
##
## Stepped like projectiles rather than simulated as a RigidBody3D - same reasoning
## (CLAUDE.md 5.1) and it keeps the throw predictable enough to aim.
##
## Started as "base for the three thrown utilities" and stayed that way until the
## Environmental archetype needed to lob a flask, which is the same object with a
## different payload. Two things had to open up for that, both of them cases where
## the player's version was one special case being treated as the only one:
## `launch_with_velocity()` (a fixed force along a direction is one way to get a
## velocity, not the only one - an enemy solves a ballistic arc to a target
## instead) and `hit_mask` (see below).

const GRAVITY: float = 18.0
## Safety net so a utility thrown off the map still returns to the pool.
const MAX_FLIGHT_TIME: float = 6.0

@export var data: UtilityData
## What the arc lands on.
##
## The player's utilities stop on enemies on purpose: a stun grenade that sails
## through the crowd it was aimed at is a wasted charge. An enemy's flask has the
## opposite need - it is lobbed *over* the horde at the player, and stopping on
## the first ally turns area denial into a puddle at its own feet. So the payload
## picks, instead of the base class assuming.
@export_flags_3d_physics var hit_mask: int = PhysicsLayers.WORLD | PhysicsLayers.ENEMY
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
	var query := PhysicsRayQueryParameters3D.create(from, to, hit_mask)
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

## Throw along `direction` at the utility's own force. The player's throw.
func launch(from: Vector3, direction: Vector3, thrower: Node) -> void:
	launch_with_velocity(from, direction * (data.throw_force if data != null else 14.0),
		thrower)


## Throw with a velocity the caller worked out. Anything that has to *arrive*
## somewhere - an enemy solving the arc to where the player is standing - has a
## velocity, not a direction and a force.
func launch_with_velocity(from: Vector3, velocity: Vector3, thrower: Node) -> void:
	global_position = from
	_thrower = thrower
	_velocity = velocity
	_flight_time = 0.0
	_fuse_left = fuse_time
	_has_landed = false
	_is_active = true
	visible = true


## La gravedad con la que este objeto vuela, para que quien resuelva un arco hacia
## el use el mismo numero. Con otro, el frasco cae corto o largo y nada lo dice.
static func get_gravity() -> float:
	return GRAVITY


func _on_acquired() -> void:
	_is_active = false
	_has_landed = false


func _on_released() -> void:
	_is_active = false
	_velocity = Vector3.ZERO
	_thrower = null


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
##
## Lee la lista de vivos de Enemy y no el grupo del arbol: get_nodes_in_group()
## arma un Array nuevo en cada llamada, y SlowField preguntaba esto en cada frame
## de fisica mientras el charco duraba. Es el mismo cambio que ya se le hizo a la
## separacion de los enemigos, por el mismo motivo.
func _enemies_in_radius(radius: float) -> Array[Enemy]:
	var result: Array[Enemy] = []
	var radius_squared: float = radius * radius
	for enemy: Enemy in Enemy.get_active_enemies():
		if enemy != null and is_instance_valid(enemy) and enemy.is_active \
				and global_position.distance_squared_to(enemy.global_position) <= radius_squared:
			result.push_back(enemy)
	return result
