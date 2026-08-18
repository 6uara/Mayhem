class_name TempWall
extends ThrownUtility
## Deploys a solid wall for a few seconds. Buys a reload, cuts a lane, or blocks a
## ranger's line - the utility that answers position rather than damage.

@export var wall_body: StaticBody3D
@export var wall_mesh: MeshInstance3D

var _time_left: float = 0.0


func _process(delta: float) -> void:
	if _time_left <= 0.0:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_dismiss()


func _activate() -> void:
	_time_left = data.effect_duration if data != null else 6.0
	_set_wall_enabled(true)
	# The wall stands where it landed, upright regardless of the throw's spin.
	rotation = Vector3(0.0, rotation.y, 0.0)
	# A wall is solid, so every machine has to be stopped by it in the same
	# place. The host's copy is the one that counts and it says where it stopped;
	# the others move onto that spot. See UtilityComponent.broadcast_landing.
	if not is_cosmetic and thrower_utility != null:
		if thrower_utility.has_method(&"broadcast_landing"):
			thrower_utility.call(&"broadcast_landing", throw_id,
				global_position, rotation.y)


## Nudged rather than re-thrown: the wall is already up on this machine, and the
## few centimetres between where it landed here and where the host put it are
## exactly the disagreement worth erasing.
func snap_to_landing(position: Vector3, yaw: float) -> void:
	global_position = position
	rotation = Vector3(0.0, yaw, 0.0)


func _on_released() -> void:
	super()
	_time_left = 0.0
	_set_wall_enabled(false)


func _dismiss() -> void:
	_set_wall_enabled(false)
	ObjectPool.release(self)


func _set_wall_enabled(enabled: bool) -> void:
	if wall_body != null:
		wall_body.collision_layer = PhysicsLayers.WORLD if enabled else 0
	if wall_mesh != null:
		wall_mesh.visible = enabled
