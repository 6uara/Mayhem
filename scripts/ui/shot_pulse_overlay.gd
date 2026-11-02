class_name ShotPulseOverlay
extends ColorRect
## A faint darkening of the screen edges on every shot, a little more on a kill.
##
## It is what is left of the hitstop's job: the hitstop gave a hit its weight by
## slowing time, and the playtest wanted shooting as fluid as possible, so the
## weight moves to the picture instead. Faint on purpose (Tokens.SHOT_PULSE_*):
## the SMG fires fifteen times a second and this must read as texture, not as
## the screen blinking. Off with "reduce flashing".

var _material: ShaderMaterial
## Seconds left on the pulse and the strength it started from.
var _time_left: float = 0.0
var _life: float = 0.0
var _peak: float = 0.0


func _ready() -> void:
	_material = material as ShaderMaterial
	EventBus.weapon_fired.connect(_on_weapon_fired.unbind(1))
	EventBus.kill_scored.connect(_on_kill_scored.unbind(4))
	_set_intensity(0.0)


func _process(delta: float) -> void:
	if _time_left <= 0.0:
		return
	_time_left = maxf(_time_left - delta, 0.0)
	_set_intensity(_peak * (_time_left / maxf(_life, 0.001)))


# Public API

## Starts a pulse, unless a stronger one is still playing: a shot landing inside
## a kill's pulse must not cut it short.
func pulse(alpha: float, life: float) -> void:
	if UiMotion.reduce_flashing():
		return
	if _current() >= alpha:
		return
	_peak = alpha
	_life = life
	_time_left = life
	_set_intensity(alpha)


func get_intensity() -> float:
	return _current()


# Private

func _current() -> float:
	return _peak * (_time_left / maxf(_life, 0.001)) if _time_left > 0.0 else 0.0


func _on_weapon_fired() -> void:
	pulse(Tokens.SHOT_PULSE_ALPHA, Tokens.SHOT_PULSE_LIFE)


func _on_kill_scored() -> void:
	pulse(Tokens.KILL_PULSE_ALPHA, Tokens.KILL_PULSE_LIFE)


## Hidden at zero so an idle overlay costs no fill at all.
func _set_intensity(value: float) -> void:
	visible = value > 0.0
	if _material != null:
		_material.set_shader_parameter(&"intensity", value)
