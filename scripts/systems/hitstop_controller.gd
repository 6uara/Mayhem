class_name HitstopController
extends Node
## A brief global time dip on a landed hit - the difference between a number
## changing on a health bar and something that reads as a physical impact.
##
## Two weights. A plain hit gets a light dip: short and shallow, a nudge rather
## than a stop. A headshot or a kill the player scored gets the full one. The
## playtest with the teachers read the old single dip (5% speed on every bullet)
## as the game freezing, and on a slow machine it was: a 50 ms window rounds up
## to two or three whole frames at 20-30 FPS, and the SMG refreshed it fifteen
## times a second, so the game barely left it while the trigger was held.
##
## Only ever triggers on damage_dealt and kill_scored, both of which are about
## damage the player dealt. Damage the player receives goes straight to
## HealthComponent.apply_damage() from the enemy side, with no hitbox and no
## signal, so this can never fire off getting hit. That asymmetry is deliberate:
## hitstop on a hit taken reads as lag, not impact.
##
## Driven by real wall-clock time (Time.get_ticks_usec), not delta - counting down
## with a delta that Engine.time_scale has itself just shrunk would make the dip
## outlast its own configured duration by whatever factor it just applied.

@export_group("Light (body hit)")
@export var duration: float = 0.03
## Time scale during a light dip. 0.3, not near-zero: the world slows, it does
## not stop, so a burst of them reads as weight and not as stutter.
@export var scale: float = 0.3
## Real seconds after a light dip ends before another one can start. Without it a
## fast weapon chains dips back to back, and that chain was the freeze.
@export var light_rearm: float = 0.15
## Below this frame rate the light dip is skipped. A dip shorter than a frame
## cannot be seen as slow motion, only as a dropped frame - exactly the stutter
## the slow machines reported.
@export var light_min_fps: float = 45.0

@export_group("Full (headshot or kill)")
@export var headshot_duration: float = 0.06
@export var kill_duration: float = 0.06
@export var full_scale: float = 0.05

var _end_at_usec: int = 0
var _rearm_at_usec: int = 0
## The scale of the dip in progress, so a light hit never weakens a full one.
var _active_scale: float = 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_physics_process(false)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.kill_scored.connect(_on_kill_scored)


func _physics_process(_delta: float) -> void:
	if Time.get_ticks_usec() < _end_at_usec:
		return
	_restore()


func _exit_tree() -> void:
	Engine.time_scale = 1.0


# Private

func _on_damage_dealt(_target: Node, amount: float, is_headshot: bool) -> void:
	if amount <= 0.0:
		return
	if is_headshot:
		_dip(headshot_duration, full_scale)
		return
	var now: int = Time.get_ticks_usec()
	if now < _end_at_usec or now < _rearm_at_usec:
		return  # Shotgun pellets and bursts share the dip already running.
	if Engine.get_frames_per_second() < light_min_fps:
		return
	_dip(duration, scale)
	_rearm_at_usec = _end_at_usec + int(light_rearm * 1_000_000.0)


func _on_kill_scored(_enemy_type: StringName, _position: Vector3, _was_headshot: bool,
		_reward: int) -> void:
	_dip(kill_duration, full_scale)


## A full dip landing on a light one deepens it and extends it; nothing ever
## makes the dip in progress shallower or shorter.
func _dip(length: float, time_scale: float) -> void:
	_active_scale = minf(_active_scale, time_scale)
	Engine.time_scale = _active_scale
	_end_at_usec = maxi(_end_at_usec, Time.get_ticks_usec() + int(length * 1_000_000.0))
	set_physics_process(true)


func _restore() -> void:
	Engine.time_scale = 1.0
	_active_scale = 1.0
	set_physics_process(false)
