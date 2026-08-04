class_name Player
extends CharacterBody3D
## First-person player root: look and weapon input only. All movement physics,
## including jump, lives in MovementComponent; grappling in GrappleComponent.

const MAX_PITCH_DEGREES: float = 89.0

## Degrees of extra FOV per m/s of ground speed above the base run.
const SPEED_FOV_PER_UNIT: float = 1.1
const SPEED_FOV_MAX: float = 12.0
const SPEED_FOV_BLEND: float = 5.0

@export_group("Nodes")
@export var head: Node3D
@export var camera: Camera3D
@export var weapon_holder: WeaponHolder
@export var recoil: CameraRecoilComponent
@export var health: HealthComponent
@export var stats: StatsComponent
@export var movement: MovementComponent
@export var grapple: GrappleComponent
@export var utility: UtilityComponent

## The equipped weapon. Everything that used to read `player.weapon` still can;
## the holder owns which one that is.
var weapon: WeaponComponent:
	get:
		return weapon_holder.current if weapon_holder != null else null

var _look_yaw: float = 0.0
var _look_pitch: float = 0.0
var _base_fov: float = 95.0
var _base_max_health: float = 100.0
var _speed_fov: float = 0.0


func _ready() -> void:
	add_to_group(&"player")
	_base_fov = float(SettingsManager.get_value("video/fov"))
	EventBus.settings_applied.connect(_on_settings_applied)
	if health != null:
		health.damaged.connect(_on_damaged)
		health.died.connect(_on_died)
		_base_max_health = health.max_health
	# Survivability upgrades live on HealthComponent, which knows nothing about
	# UpgradeManager - the player is what bridges them.
	UpgradeManager.upgrades_changed.connect(_apply_survivability_stats)
	_apply_survivability_stats()
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

	if weapon_holder != null and weapon_holder.handle_input(event):
		return
	if utility != null and utility.handle_input(event):
		return

	var equipped: WeaponComponent = weapon
	if equipped == null:
		return
	# A weapon mid-swap is not in the player's hands yet.
	if weapon_holder != null and weapon_holder.is_swapping:
		equipped.set_trigger(false)
		return

	if event.is_action_pressed("fire"):
		equipped.set_trigger(true)
	elif event.is_action_released("fire"):
		equipped.set_trigger(false)
	elif event.is_action_pressed("ads"):
		equipped.set_ads(true)
	elif event.is_action_released("ads"):
		equipped.set_ads(false)
	elif event.is_action_pressed("reload"):
		equipped.try_reload()
	elif event.is_action_pressed("interact"):
		_try_interact()


func _process(delta: float) -> void:
	_apply_look()
	_apply_fov(delta)


# Public API

## Where bullets actually go: look plus recoil aim offset, never the cosmetic kick.
func get_aim_transform() -> Transform3D:
	return head.global_transform if head != null else global_transform


# Private

## Zip lines are the only interactable in the slice, so this stays a direct look-up
## rather than a general interaction system.
func _try_interact() -> void:
	var ray: RayCast3D = head.get_node_or_null("InteractionRay") if head != null else null
	if ray == null:
		return
	ray.force_raycast_update()
	if not ray.is_colliding():
		return
	var line := ray.get_collider() as Node
	while line != null and not (line is ZipLine):
		line = line.get_parent()
	if line is ZipLine:
		(line as ZipLine).try_mount(self)


func _apply_look() -> void:
	var offset: Vector2 = recoil.aim_offset if recoil != null else Vector2.ZERO
	rotation.y = deg_to_rad(_look_yaw + offset.x)
	if head != null:
		head.rotation.x = deg_to_rad(clampf(_look_pitch + offset.y,
			-MAX_PITCH_DEGREES, MAX_PITCH_DEGREES))


func _apply_fov(delta: float) -> void:
	if camera == null:
		return
	var target: float = weapon.get_current_fov(_base_fov) if weapon != null else _base_fov
	camera.fov = target + _tick_speed_fov(delta)


## Widens the view as ground speed climbs past a normal run.
##
## Sense of speed is a camera property, not a physics one. The movement system hands
## out real momentum through slides, dashes and pads, but without this the screen
## looks identical at 7 m/s and 14 - so the reward for chaining well is invisible,
## and the whole thing reads as gliding. Suppressed while aiming, where a drifting
## FOV would fight the sight picture rather than sell anything.
func _tick_speed_fov(delta: float) -> float:
	var goal: float = 0.0
	if movement != null:
		var speed: float = Vector3(velocity.x, 0.0, velocity.z).length()
		var excess: float = speed - movement.base_move_speed
		if excess > 0.0:
			goal = minf(excess * SPEED_FOV_PER_UNIT, SPEED_FOV_MAX)
	if weapon != null:
		goal *= 1.0 - weapon.ads_progress
	_speed_fov = lerpf(_speed_fov, goal, clampf(SPEED_FOV_BLEND * delta, 0.0, 1.0))
	return _speed_fov


func _is_ads() -> bool:
	return weapon != null and weapon.is_ads


## Max health preserves the current fraction, so buying Plating mid-run tops the
## player up proportionally rather than handing out a free full heal.
func _apply_survivability_stats() -> void:
	if health == null or stats == null:
		return
	health.set_max_health(stats.get_stat_from(StatsComponent.MAX_HEALTH, _base_max_health))
	health.damage_taken_multiplier = stats.get_stat_from(
		StatsComponent.DAMAGE_TAKEN_MULTIPLIER, 1.0)


func _on_settings_applied() -> void:
	_base_fov = float(SettingsManager.get_value("video/fov"))


func _on_damaged(amount: float, remaining: float) -> void:
	EventBus.player_damaged.emit(amount, remaining)


func _on_died() -> void:
	EventBus.player_died.emit()
