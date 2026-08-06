class_name PlayerBodyAnimator
extends Node3D
## Drives the UAL1 mannequin's AnimationPlayer off MovementComponent's own state and
## HealthComponent's death signal - never off a second copy of "is the player moving"
## kept here. The body is grey-box like the rest of the cast: only the clips that
## already exist in the UAL1 library are used, nothing authored or retimed.
##
## This body is not what the player sees - it is what the world sees. `mesh_instance`
## is pushed onto `own_body_layer` and excluded from `camera`'s cull_mask in _ready(),
## the same first-person trick every shooter uses to keep a shadow-casting, animated
## body without it filling the view or clipping through the camera.

@export var movement: MovementComponent
@export var health: HealthComponent
@export var camera: Camera3D
@export var animation_player: AnimationPlayer
@export var mesh_instance: MeshInstance3D
## Render layer (1-20) the body is pushed onto and the camera is told to ignore.
@export_range(1, 20) var own_body_layer: int = 20

@export_group("Ground speed tiers")
## Below this, standing still reads as standing still.
@export var idle_speed: float = 0.5
@export var walk_speed: float = 4.0
@export var jog_speed: float = 7.0

@export_group("Blend")
@export var blend_time: float = 0.2

var _land_lock_left: float = 0.0
var _was_airborne: bool = false

const LAND_LOCK_TIME: float = 0.35


func _ready() -> void:
	if mesh_instance != null:
		mesh_instance.layers = 1 << (own_body_layer - 1)
	if camera != null:
		camera.cull_mask &= ~(1 << (own_body_layer - 1))
	if movement != null:
		movement.landed.connect(_on_landed)
	if health != null:
		health.died.connect(_on_died)


func _physics_process(delta: float) -> void:
	if movement == null or animation_player == null or movement.body == null:
		return
	if health != null and health.is_dead:
		return

	_land_lock_left = maxf(_land_lock_left - delta, 0.0)
	if _land_lock_left > 0.0:
		return

	var body: CharacterBody3D = movement.body
	var horizontal: Vector3 = Vector3(body.velocity.x, 0.0, body.velocity.z)
	var speed: float = horizontal.length()

	match movement.state:
		MovementComponent.State.SLIDING:
			_play("Crouch_Fwd" if speed > idle_speed else "Crouch_Idle")
		MovementComponent.State.AIRBORNE, MovementComponent.State.GRAPPLING:
			_tick_airborne()
		MovementComponent.State.DASHING:
			_play("Sprint")
		_:
			_play(_grounded_clip(speed))
	_was_airborne = movement.state in [MovementComponent.State.AIRBORNE, MovementComponent.State.GRAPPLING]


# Private

func _grounded_clip(speed: float) -> StringName:
	if speed < idle_speed:
		return &"Idle"
	if speed < walk_speed:
		return &"Walk"
	if speed < jog_speed:
		return &"Jog_Fwd"
	return &"Sprint"


## A jump entered from the ground gets its wind-up; falling off a ledge with no jump
## does not - there was nothing to wind up from. Either way it settles into the same
## airborne loop, which also covers grappling since both leave the ground under you.
func _tick_airborne() -> void:
	if not _was_airborne:
		if movement.body.velocity.y > 0.0:
			_play("Jump_Start", 0.05)
		else:
			_play("Jump")
		return
	if animation_player.current_animation == "Jump_Start" \
			and animation_player.is_playing():
		return
	_play("Jump")


func _play(clip: StringName, custom_blend: float = -1.0) -> void:
	if animation_player.current_animation == String(clip) and animation_player.is_playing():
		return
	if not animation_player.has_animation(String(clip)):
		return
	animation_player.play(clip, custom_blend if custom_blend >= 0.0 else blend_time)


func _on_landed(_fall_speed: float) -> void:
	if animation_player == null or not animation_player.has_animation("Jump_Land"):
		return
	animation_player.play(&"Jump_Land", 0.05)
	_land_lock_left = LAND_LOCK_TIME


func _on_died() -> void:
	if animation_player != null and animation_player.has_animation("Death01"):
		animation_player.play(&"Death01", 0.1)
