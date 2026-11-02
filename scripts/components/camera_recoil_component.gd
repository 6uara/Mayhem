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

@export_group("Shake")
## A light shake on every shot, the weight the hitstop used to give a hit
## (removed 2026-11-02: shooting has to stay fluid). Trauma model: each shot adds
## `shot_shake` times the pattern's `visual_kick_multiplier`, trauma decays at
## `shake_decay` per second, and the shake is trauma times the amplitudes below.
## The SMG settles around 0.3 of trauma under full auto; a single pistol shot is
## about a tenth of a degree of roll. Roll and a few millimetres of sway only -
## it lives on the rig, under the aim pivot, so it can never move a shot.
@export var shot_shake: float = 0.25
@export var shake_decay: float = 5.0
@export var shake_roll_degrees: float = 0.4
@export var shake_offset: float = 0.004
@export var shake_frequency: float = 24.0

## Accumulated aim rotation in degrees (x = yaw, y = pitch). Read by the player.
var aim_offset: Vector2 = Vector2.ZERO

var _recovery_speed: float = 12.0
var _visual_offset: Vector2 = Vector2.ZERO
var _trauma: float = 0.0
var _shake_time: float = 0.0


func _process(delta: float) -> void:
	if aim_offset != Vector2.ZERO:
		aim_offset = aim_offset.move_toward(Vector2.ZERO, _recovery_speed * delta)
	if _visual_offset != Vector2.ZERO:
		_visual_offset = _visual_offset.move_toward(Vector2.ZERO, visual_recovery_speed * delta)
	var roll: float = 0.0
	var sway := Vector3.ZERO
	if _trauma > 0.0:
		_trauma = maxf(_trauma - shake_decay * delta, 0.0)
		_shake_time += delta
		# Three sines at unrelated rates instead of noise: smooth, never repeats
		# visibly over a fraction of a second, and costs nothing.
		var t: float = _shake_time * shake_frequency
		roll = sin(t * 1.0 + 0.7) * shake_roll_degrees * _trauma
		sway = Vector3(sin(t * 1.37 + 2.1), sin(t * 0.83 + 4.3), 0.0) * shake_offset * _trauma
	if camera_rig != null:
		camera_rig.rotation_degrees = Vector3(_visual_offset.y, _visual_offset.x, roll)
		camera_rig.position = sway


# Public API

## `pattern_offset` is the deterministic per-shot offset in degrees, already scaled by
## any recoil-reduction upgrades. x = horizontal, y = vertical (positive = up).
func apply_shot(pattern_offset: Vector2, recovery_speed: float, visual_multiplier: float) -> void:
	_recovery_speed = recovery_speed
	aim_offset += pattern_offset
	if bool(SettingsManager.get_value("accessibility/screenshake_enabled")):
		_visual_offset += pattern_offset * visual_kick_scale * visual_multiplier
		_trauma = minf(_trauma + shot_shake * visual_multiplier, 1.0)


## How much shake is left, 0 at rest.
func get_trauma() -> float:
	return _trauma


func reset() -> void:
	aim_offset = Vector2.ZERO
	_visual_offset = Vector2.ZERO
	_trauma = 0.0
	if camera_rig != null:
		camera_rig.rotation_degrees = Vector3.ZERO
		camera_rig.position = Vector3.ZERO
