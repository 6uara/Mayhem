class_name Player
extends CharacterBody3D
## First-person player root: look and weapon input only. All movement physics,
## including jump, lives in MovementComponent; grappling in GrappleComponent.

const MAX_PITCH_DEGREES: float = 89.0

@export_group("Nodes")
@export var head: Node3D
@export var camera: Camera3D
@export var weapon: WeaponComponent
@export var recoil: CameraRecoilComponent
@export var health: HealthComponent
@export var stats: StatsComponent
@export var movement: MovementComponent
@export var grapple: GrappleComponent

var _look_yaw: float = 0.0
var _look_pitch: float = 0.0
var _base_fov: float = 95.0


func _ready() -> void:
	add_to_group(&"player")
	_base_fov = float(SettingsManager.get_value("video/fov"))
	EventBus.settings_applied.connect(_on_settings_applied)
	if health != null:
		health.damaged.connect(_on_damaged)
		health.died.connect(_on_died)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity: float = SettingsManager.get_mouse_sensitivity(_is_ads())
		if bool(SettingsManager.get_value("input/invert_y")):
			sensitivity = -sensitivity
		_look_yaw -= motion.relative.x * sensitivity
		_look_pitch = clampf(_look_pitch - motion.relative.y * sensitivity,
			-MAX_PITCH_DEGREES, MAX_PITCH_DEGREES)
		return

	if weapon == null:
		return
	if event.is_action_pressed("fire"):
		weapon.set_trigger(true)
	elif event.is_action_released("fire"):
		weapon.set_trigger(false)
	elif event.is_action_pressed("ads"):
		weapon.set_ads(true)
	elif event.is_action_released("ads"):
		weapon.set_ads(false)
	elif event.is_action_pressed("reload"):
		weapon.try_reload()


func _process(_delta: float) -> void:
	_apply_look()
	_apply_fov()


# Public API

## Where bullets actually go: look plus recoil aim offset, never the cosmetic kick.
func get_aim_transform() -> Transform3D:
	return head.global_transform if head != null else global_transform


# Private

func _apply_look() -> void:
	var offset: Vector2 = recoil.aim_offset if recoil != null else Vector2.ZERO
	rotation.y = deg_to_rad(_look_yaw + offset.x)
	if head != null:
		head.rotation.x = deg_to_rad(clampf(_look_pitch + offset.y,
			-MAX_PITCH_DEGREES, MAX_PITCH_DEGREES))


func _apply_fov() -> void:
	if camera == null:
		return
	camera.fov = weapon.get_current_fov(_base_fov) if weapon != null else _base_fov


func _is_ads() -> bool:
	return weapon != null and weapon.is_ads


func _on_settings_applied() -> void:
	_base_fov = float(SettingsManager.get_value("video/fov"))


func _on_damaged(amount: float, remaining: float) -> void:
	EventBus.player_damaged.emit(amount, remaining)


func _on_died() -> void:
	EventBus.player_died.emit()
