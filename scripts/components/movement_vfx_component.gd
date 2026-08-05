class_name MovementVfxComponent
extends Node
## Cosmetic-only feedback for the two moves speed is built and spent on: a burst
## trail on dash, and a stream of sparks for as long as a slide lasts. Neither
## reads a value MovementComponent doesn't already publish - dash comes off
## EventBus.dash_used (fired once, on the frame a charge is spent) and slide
## comes off MovementComponent.state_changed (entered/left State.SLIDING).
##
## Grey-box art like the rest of the Phase 1/2 VFX pass - replaced in Phase 5.

@export var movement: MovementComponent
@export var dash_trail: GPUParticles3D
@export var slide_sparks: GPUParticles3D


func _ready() -> void:
	EventBus.dash_used.connect(_on_dash_used)
	if movement != null:
		movement.state_changed.connect(_on_state_changed)


func _on_dash_used(_charges_remaining: int) -> void:
	if dash_trail == null:
		return
	dash_trail.restart()
	dash_trail.emitting = true


func _on_state_changed(new_state: MovementComponent.State) -> void:
	if slide_sparks == null:
		return
	slide_sparks.emitting = new_state == MovementComponent.State.SLIDING
