class_name DisappearingPlatform
extends Node3D
## Solid until stepped on, then it warns and vanishes.
##
## The warning is learnable by construction: a fixed 1.5s, blinking on a 0.25s step
## that accelerates to 0.1s in the final 0.4s. Same delay every time, so a player
## can route through these at speed once they have felt it once - which is the whole
## point of a movement hazard rather than a trap.
##
## Gone leaves a dashed grey outline behind, so the return trip can be planned.

signal vanished()
signal restored()

enum State { SOLID, WARNING, GONE }

@export var body: StaticBody3D
@export var solid_mesh: MeshInstance3D
@export var ghost_mesh: MeshInstance3D
@export var telegraph: TelegraphComponent
@export var respawn_time: float = 4.0

@export_group("Audio")
@export var warning_sound: AudioStream
@export var vanish_sound: AudioStream

var state: State = State.SOLID

var _timer: float = 0.0
var _trigger: Area3D


func _ready() -> void:
	add_to_group(&"disappearing_platform")
	_trigger = get_node_or_null("Trigger") as Area3D
	if _trigger != null:
		_trigger.body_entered.connect(_on_stepped_on)
	_set_state(State.SOLID)


func _process(delta: float) -> void:
	if state == State.SOLID:
		return
	_timer -= delta

	if state == State.WARNING:
		# Accelerate the blink for the last 0.4s: the deadline should feel closer.
		var remaining: float = _timer
		if telegraph != null:
			telegraph.set_blink_step(Tokens.PLATFORM_BLINK_FAST if remaining <= 0.4
				else Tokens.PLATFORM_BLINK_STEP)
		if _timer <= 0.0:
			_vanish()
		return

	if _timer <= 0.0:
		_set_state(State.SOLID)
		restored.emit()


# Public API

## Starts the countdown. Stepping on an already-warning platform does not restart
## it - the deadline belongs to the platform, not to the last footstep.
func trigger() -> void:
	if state != State.SOLID:
		return
	_set_state(State.WARNING)
	AudioPool.play_3d(warning_sound, global_position, AudioPool.BUS_WORLD)


# Private

func _on_stepped_on(entered: Node3D) -> void:
	if entered.is_in_group(&"player"):
		trigger()


func _vanish() -> void:
	_set_state(State.GONE)
	AudioPool.play_3d(vanish_sound, global_position, AudioPool.BUS_WORLD)
	vanished.emit()


func _set_state(new_state: State) -> void:
	state = new_state
	match state:
		State.SOLID:
			_timer = 0.0
			_set_solid(true)
			if telegraph != null:
				telegraph.state = TelegraphComponent.State.AVAILABLE
		State.WARNING:
			_timer = Tokens.PLATFORM_WARNING
			_set_solid(true)
			if telegraph != null:
				telegraph.set_blink_step(Tokens.PLATFORM_BLINK_STEP)
				telegraph.state = TelegraphComponent.State.WARNING
		State.GONE:
			_timer = respawn_time
			_set_solid(false)
			if telegraph != null:
				telegraph.state = TelegraphComponent.State.IDLE


func _set_solid(is_solid: bool) -> void:
	if body != null:
		# Layer 0 rather than disabling the node, so nothing else has to know.
		body.collision_layer = PhysicsLayers.WORLD if is_solid else 0
	if solid_mesh != null:
		solid_mesh.visible = is_solid
	# The ghost outline stays while it is gone, so the route back is still readable.
	if ghost_mesh != null:
		ghost_mesh.visible = not is_solid
