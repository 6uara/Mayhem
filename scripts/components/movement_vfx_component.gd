class_name MovementVfxComponent
extends Node
## Cosmetic-only feedback for the two moves speed is built and spent on: a burst
## trail when a fast fall lands into a slide, and a stream of sparks for as long
## as a slide lasts. Neither reads a value MovementComponent doesn't already
## publish - the dive comes off MovementComponent.fast_fall_landed (fired once,
## on the landing frame) and slide comes off MovementComponent.state_changed
## (entered/left State.SLIDING). The trail was the dash's until the dash left
## (2026-10-21).
##
## Grey-box art like the rest of the Phase 1/2 VFX pass - replaced in Phase 5.

@export var movement: MovementComponent
@export var dive_trail: GPUParticles3D
@export var slide_sparks: GPUParticles3D


func _ready() -> void:
	if movement != null:
		movement.fast_fall_landed.connect(_on_fast_fall_landed.unbind(1))
		movement.state_changed.connect(_on_state_changed)


func _on_fast_fall_landed() -> void:
	if dive_trail == null:
		return
	dive_trail.restart()
	dive_trail.emitting = true


func _on_state_changed(new_state: MovementComponent.State) -> void:
	if slide_sparks == null:
		return
	slide_sparks.emitting = new_state == MovementComponent.State.SLIDING
