class_name SpeedLinesOverlay
extends ColorRect
## Screen-space speed-line vignette, driven by the player's real horizontal
## speed (not the target speed MovementComponent.get_move_speed() returns -
## the same "excess over a normal run" Player._tick_speed_fov() already
## computes for FOV). Purely cosmetic, the visual half of the same reward the
## FOV widening is the camera half of: the movement system hands out real
## momentum through slides, dashes and pads, but without a visible
## consequence 7 m/s and 14 look identical on screen.

## Below this horizontal speed the overlay is fully invisible.
@export var min_speed: float = 9.0
## At or above this speed the overlay sits at full intensity. A tuning knob,
## not a hardcoded threshold - deliberately exported rather than baked into
## the mapping, since what counts as "fast" depends on the mobility upgrade
## catalogue's own numbers.
@export var max_speed: float = 20.0
## How fast the shown intensity chases its target. Without this, a strafe
## correction or a half-second of ground friction would flicker the overlay
## on and off instead of reading as a smooth ramp.
@export var smoothing: float = 6.0

var _material: ShaderMaterial
var _target_intensity: float = 0.0
var _shown_intensity: float = 0.0


func _ready() -> void:
	_material = material as ShaderMaterial
	_set_intensity(0.0)


## Physics, not idle process - idle _process frames don't reliably advance
## under the headless test runner (the same reason HitstopController ticks on
## _physics_process too; see its own docstring). No visual cost either way at
## typical frame/physics rates.
func _physics_process(delta: float) -> void:
	if is_equal_approx(_shown_intensity, _target_intensity):
		return
	_shown_intensity = move_toward(_shown_intensity, _target_intensity, smoothing * delta)
	_set_intensity(_shown_intensity)


## Called every frame from HUD._tick_movement() with the player's actual
## horizontal speed (not a 0..1 fraction) - the mapping, and its tuning, live
## in exactly one place.
func set_speed(horizontal_speed: float) -> void:
	if max_speed <= min_speed or not bool(SettingsManager.get_value(
			"accessibility/speed_lines_enabled", true)):
		_target_intensity = 0.0
		return
	_target_intensity = clampf(
		(horizontal_speed - min_speed) / (max_speed - min_speed), 0.0, 1.0)


func _set_intensity(value: float) -> void:
	if _material != null:
		_material.set_shader_parameter(&"intensity", value)
