class_name CameraRecoilComponent
extends Node
## Splits recoil into the two things it actually is:
##   `aim_offset`  - rotates where the player is looking, so it changes where bullets go.
##                   The player can (and should) learn to compensate for it with the mouse.
##   visual kick   - a cosmetic punch on the camera rig only. Always returns in full and
##                   never affects aim. Disabled by the screenshake accessibility setting.
##
## The player composes `aim_offset` into its yaw/pitch; the rig node is driven here.
## Phantom Camera can take over the rig node later without touching aim_offset.

## Cosmetic node between HeadPivot and Camera3D. Visual kick is applied here.
@export var camera_rig: Node3D
@export var visual_recovery_speed: float = 14.0
## Degrees of visual punch per 1.0 of pattern magnitude.
@export var visual_kick_scale: float = 0.6

## Accumulated aim rotation in degrees (x = yaw, y = pitch). Read by the player.
var aim_offset: Vector2 = Vector2.ZERO

var _recovery_speed: float = 12.0
var _visual_offset: Vector2 = Vector2.ZERO


func _process(delta: float) -> void:
	if aim_offset != Vector2.ZERO:
		aim_offset = aim_offset.move_toward(Vector2.ZERO, _recovery_speed * delta)
	if _visual_offset != Vector2.ZERO:
		_visual_offset = _visual_offset.move_toward(Vector2.ZERO, visual_recovery_speed * delta)
	if camera_rig != null:
		camera_rig.rotation_degrees = Vector3(_visual_offset.y, _visual_offset.x, 0.0)


# Public API

## `pattern_offset` is the deterministic per-shot offset in degrees, already scaled by
## any recoil-reduction upgrades. x = horizontal, y = vertical (positive = up).
func apply_shot(pattern_offset: Vector2, recovery_speed: float, visual_multiplier: float) -> void:
	_recovery_speed = recovery_speed
	aim_offset += pattern_offset
	if bool(SettingsManager.get_value("accessibility/screenshake_enabled")):
		_visual_offset += pattern_offset * visual_kick_scale * visual_multiplier


func reset() -> void:
	aim_offset = Vector2.ZERO
	_visual_offset = Vector2.ZERO
	if camera_rig != null:
		camera_rig.rotation_degrees = Vector3.ZERO
