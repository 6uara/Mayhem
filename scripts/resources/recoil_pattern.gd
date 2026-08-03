class_name RecoilPattern
extends Resource
## Deterministic, learnable per-shot recoil offsets. Horizontal randomness is forbidden.

## Per-shot aim offsets in degrees. x = horizontal, y = vertical (positive = up).
@export var points: PackedVector2Array = PackedVector2Array()
## Index the pattern loops back to once it runs past the end of `points`.
## Set to -1 to clamp on the last point instead of looping.
@export var loop_after_index: int = -1
## Seconds without firing before the pattern index resets to 0.
@export var reset_time: float = 0.35
## How fast the camera returns toward the pre-spray origin (degrees/second).
@export var recovery_speed: float = 12.0
## Cosmetic camera punch multiplier. Never affects where projectiles go.
@export var visual_kick_multiplier: float = 1.0


## Returns the aim offset for `shot_index`, scaled by `magnitude_scale`
## (upgrades scale the pattern - they never randomize it).
func get_offset(shot_index: int, magnitude_scale: float = 1.0) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var index: int = _resolve_index(shot_index)
	return points[index] * magnitude_scale


func _resolve_index(shot_index: int) -> int:
	var last: int = points.size() - 1
	if shot_index <= last:
		return maxi(shot_index, 0)
	if loop_after_index < 0 or loop_after_index > last:
		return last
	var loop_length: int = last - loop_after_index + 1
	return loop_after_index + (shot_index - loop_after_index) % loop_length
