class_name Viewmodel
extends Node3D
## Weapon viewmodel rendered in its own SubViewport world, so it can never clip
## through level geometry. Grey-box placeholder mesh until the art pass.
##
## Kick here is purely cosmetic: it moves the model, never the aim.

@export var muzzle_flash: Node3D
@export var camera: Camera3D

@export_group("Feel")
@export var kick_back: float = 0.06
@export var kick_up_degrees: float = 2.5
@export var kick_recovery: float = 12.0
@export var ads_position: Vector3 = Vector3(0.0, -0.06, -0.28)
@export var sway_amount: float = 0.02

const MUZZLE_FLASH_TIME: float = 0.045

var _rest_position: Vector3 = Vector3.ZERO
var _kick_offset: Vector3 = Vector3.ZERO
var _kick_rotation: float = 0.0
var _flash_timer: float = 0.0
var _weapon: WeaponComponent
var _sway: Vector2 = Vector2.ZERO


func _ready() -> void:
	_rest_position = position
	if muzzle_flash != null:
		muzzle_flash.visible = false
	_bind_weapon.call_deferred()


func _process(delta: float) -> void:
	_kick_offset = _kick_offset.move_toward(Vector3.ZERO, kick_recovery * delta * 0.1)
	_kick_rotation = move_toward(_kick_rotation, 0.0, kick_recovery * delta)

	var target: Vector3 = _rest_position
	if _weapon != null:
		target = _rest_position.lerp(ads_position, _weapon.ads_progress)
		if camera != null:
			camera.fov = _weapon.get_current_fov(75.0)
	position = target + _kick_offset + Vector3(_sway.x, _sway.y, 0.0)
	rotation_degrees.x = _kick_rotation

	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0 and muzzle_flash != null:
			muzzle_flash.visible = false


func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	_sway = (-motion.relative * sway_amount * 0.01).limit_length(0.04)


# Private

func _bind_weapon() -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player == null or player.weapon == null:
		push_warning("Viewmodel: no player weapon found, kick disabled")
		return
	_weapon = player.weapon
	_weapon.fired.connect(_on_fired)


func _on_fired(_shot_index: int) -> void:
	_kick_offset.z += kick_back
	_kick_rotation += kick_up_degrees
	if muzzle_flash != null:
		muzzle_flash.visible = true
		_flash_timer = MUZZLE_FLASH_TIME
