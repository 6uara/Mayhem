class_name HitstopController
extends Node
## A brief global time dip on a landed hit - the difference between a number
## changing on a health bar and something that reads as a physical impact.
##
## Only ever triggers on damage_dealt, which HitboxComponent is the only emitter
## of - and only enemies (and the target dummy) own a HitboxComponent. Damage the
## player receives goes straight to HealthComponent.apply_damage() from the enemy
## side, with no hitbox and no signal, so this can never fire off getting hit
## rather than landing a hit. That asymmetry is deliberate: hitstop on a hit taken
## reads as lag, not impact.
##
## Driven by real wall-clock time (Time.get_ticks_usec), not delta - counting down
## with a delta that Engine.time_scale has itself just shrunk would make the dip
## outlast its own configured duration by whatever factor it just applied.

@export var duration: float = 0.05
@export var headshot_duration: float = 0.09
@export var scale: float = 0.05

var _end_at_usec: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_physics_process(false)
	EventBus.damage_dealt.connect(_on_damage_dealt)


func _physics_process(_delta: float) -> void:
	if Time.get_ticks_usec() < _end_at_usec:
		return
	Engine.time_scale = 1.0
	set_physics_process(false)


func _exit_tree() -> void:
	Engine.time_scale = 1.0


# Private

func _on_damage_dealt(_target: Node, amount: float, is_headshot: bool) -> void:
	if amount <= 0.0:
		return
	var length: float = headshot_duration if is_headshot else duration
	Engine.time_scale = scale
	_end_at_usec = Time.get_ticks_usec() + int(length * 1_000_000.0)
	set_physics_process(true)
