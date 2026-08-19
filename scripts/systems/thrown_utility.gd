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
