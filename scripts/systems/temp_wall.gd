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
