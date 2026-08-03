class_name WeaponComponent
extends Node3D
## One equipped weapon: firing, deterministic recoil, spread, ADS, reload and ammo.
## All numbers come from `data`; upgrades layer on through StatsComponent.

signal fired(shot_index: int)
signal reload_started(duration: float)
signal reload_finished()
signal ammo_changed(current: int, reserve: int)
signal ads_changed(is_ads: bool)

@export var data: WeaponData
## Aim source - the head pivot, not the camera, so cosmetic kick never moves bullets.
@export var aim_node: Node3D
## Visual muzzle position, used for the tracer's spawn point and muzzle flash.
@export var muzzle: Node3D
@export var recoil: CameraRecoilComponent
@export var stats: StatsComponent
@export var body: CharacterBody3D

@export_group("Audio")
@export var fire_sound: AudioStream
@export var reload_sound: AudioStream
@export var empty_sound: AudioStream

var is_reloading: bool = false
var is_ads: bool = false
## 0 = hipfire, 1 = fully aimed. Drives FOV and spread interpolation.
var ads_progress: float = 0.0

var _ammo: int = 0
var _reserve: int = 0
var _shot_index: int = 0
var _time_since_shot: float = 999.0
var _cooldown: float = 0.0
var _is_trigger_held: bool = false
var _reload_timer: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if data == null:
		push_warning("WeaponComponent on %s has no WeaponData" % get_path())
		set_process(false)
		return
	_rng.randomize()
	_ammo = get_magazine_size()
	_reserve = get_reserve_max()
	_emit_ammo()


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_time_since_shot += delta
	_tick_reload(delta)
	_tick_ads(delta)
	_tick_recoil_reset()
	if _is_trigger_held:
		_try_fire()


# Public API

func set_trigger(held: bool) -> void:
	_is_trigger_held = held
	if held:
		_try_fire()


func set_ads(value: bool) -> void:
	if is_ads == value:
		return
	is_ads = value
	ads_changed.emit(is_ads)


func try_reload() -> bool:
	if is_reloading or data == null:
		return false
	if _ammo >= get_magazine_size() or _reserve <= 0:
		return false
	is_reloading = true
	_reload_timer = get_reload_time()
	reload_started.emit(_reload_timer)
	AudioPool.play_3d(reload_sound, global_position, AudioPool.BUS_WEAPONS)
	return true


## Adds reserve ammo from a pickup. Returns the amount actually taken -
## the overflow is left in the world rather than silently discarded.
func add_reserve_ammo(amount: int) -> int:
	var space: int = get_reserve_max() - _reserve
	var taken: int = clampi(amount, 0, maxi(space, 0))
	_reserve += taken
	if taken > 0:
		_emit_ammo()
	return taken


## Re-announces this weapon's ammo. Called by WeaponHolder on equip so the HUD
## shows the new weapon's counts rather than the previous one's.
func notify_equipped() -> void:
	_is_trigger_held = false
	is_ads = false
	ads_progress = 0.0
	_emit_ammo()


## Back to a full magazine and reserve. Used between runs, not between waves -
## nothing carries across runs (CLAUDE.md 5.5).
func reset() -> void:
	is_reloading = false
	_reload_timer = 0.0
	_shot_index = 0
	_cooldown = 0.0
	_is_trigger_held = false
	is_ads = false
	ads_progress = 0.0
	_ammo = get_magazine_size()
	_reserve = get_reserve_max()
	_emit_ammo()


func get_ammo() -> int:
	return _ammo


func get_reserve() -> int:
	return _reserve


func get_shot_index() -> int:
	return _shot_index


func is_empty() -> bool:
	return _ammo <= 0


func get_current_fov(base_fov: float) -> float:
	if data == null:
		return base_fov
	return lerpf(base_fov, data.ads_fov, ads_progress)


func get_move_speed_multiplier() -> float:
	if data == null:
		return 1.0
	return lerpf(1.0, data.ads_move_speed_multiplier, ads_progress)


# Upgrade-aware stat reads

func get_magazine_size() -> int:
	return int(round(_stat(StatsComponent.MAGAZINE_SIZE, float(data.magazine_size))))


func get_reserve_max() -> int:
	return int(round(_stat(StatsComponent.RESERVE_AMMO_MAX, float(data.reserve_ammo_max))))


func get_reload_time() -> float:
	return maxf(_stat(StatsComponent.RELOAD_TIME, data.reload_time), 0.05)


func get_fire_rate() -> float:
	return maxf(_stat(StatsComponent.FIRE_RATE, data.fire_rate), 0.01)


func get_damage() -> float:
	return _stat(StatsComponent.WEAPON_DAMAGE, data.damage)


# Private

func _try_fire() -> void:
	if data == null or is_reloading or _cooldown > 0.0:
		return
	if _ammo <= 0:
		_on_empty()
		return

	_ammo -= 1
	_cooldown = 1.0 / get_fire_rate()
	_time_since_shot = 0.0

	# Projectiles leave from the aim origin, not the muzzle: a muzzle-offset spawn
	# does not line up with the crosshair at close range, which reads as the weapon
	# being inaccurate. The muzzle drives the flash only.
	var origin: Vector3 = aim_node.global_position
	var aim: Vector3 = -aim_node.global_transform.basis.z
	var spread: float = get_current_spread()
	for _i: int in maxi(data.projectiles_per_shot, 1):
		_spawn_projectile(origin, _apply_spread(aim, spread))

	_apply_recoil()
	AudioPool.play_3d(fire_sound, global_position, AudioPool.BUS_WEAPONS)
	fired.emit(_shot_index)
	EventBus.weapon_fired.emit(data.id)
	_shot_index += 1
	_emit_ammo()

	if _ammo <= 0:
		try_reload()


func _spawn_projectile(origin: Vector3, direction: Vector3) -> void:
	if data.projectile_scene == null:
		push_warning("WeaponComponent: %s has no projectile_scene" % data.id)
		return
	var projectile: Node = ObjectPool.acquire(data.projectile_scene)
	var typed := projectile as Projectile
	if typed == null:
		push_error("WeaponComponent: %s projectile_scene is not a Projectile" % data.id)
		return
	typed.launch(origin, direction, data, body, get_damage())


## Spread cone half-angle in degrees, including ADS, movement and airborne penalties.
func get_current_spread() -> float:
	var base: float = lerpf(data.spread_hipfire, data.spread_ads, ads_progress)
	if body != null:
		if not body.is_on_floor():
			base *= data.spread_airborne_multiplier
		elif body.velocity.length() > 0.1:
			base *= data.spread_moving_multiplier
	return _stat(StatsComponent.SPREAD_MULTIPLIER, base)


## Random cone deviation. Spread is allowed to be random; the recoil pattern is not.
func _apply_spread(direction: Vector3, spread_degrees: float) -> Vector3:
	if spread_degrees <= 0.0:
		return direction
	var aim_basis: Basis = aim_node.global_transform.basis
	var angle: float = _rng.randf_range(0.0, TAU)
	var magnitude: float = deg_to_rad(spread_degrees) * sqrt(_rng.randf())
	var offset: Vector3 = (aim_basis.x * cos(angle) + aim_basis.y * sin(angle)) * tan(magnitude)
	return (direction + offset).normalized()


func _apply_recoil() -> void:
	if recoil == null or data.recoil_pattern == null:
		return
	var pattern: RecoilPattern = data.recoil_pattern
	var magnitude: float = _stat(StatsComponent.RECOIL_MAGNITUDE, 1.0)
	recoil.apply_shot(pattern.get_offset(_shot_index, magnitude), pattern.recovery_speed,
		pattern.visual_kick_multiplier)


## The pattern index resets after `reset_time` without firing - this is what makes
## a spray learnable: the same trigger discipline always produces the same pattern.
func _tick_recoil_reset() -> void:
	if _shot_index == 0 or data.recoil_pattern == null:
		return
	if _time_since_shot >= data.recoil_pattern.reset_time:
		_shot_index = 0


func _tick_reload(delta: float) -> void:
	if not is_reloading:
		return
	_reload_timer -= delta
	if _reload_timer > 0.0:
		return
	is_reloading = false
	var needed: int = get_magazine_size() - _ammo
	var taken: int = mini(needed, _reserve)
	_ammo += taken
	_reserve -= taken
	_shot_index = 0
	reload_finished.emit()
	EventBus.weapon_reloaded.emit(data.id)
	_emit_ammo()


func _tick_ads(delta: float) -> void:
	var transition: float = maxf(_stat(StatsComponent.ADS_TRANSITION_TIME,
		data.ads_transition_time), 0.01)
	var target: float = 1.0 if is_ads else 0.0
	ads_progress = move_toward(ads_progress, target, delta / transition)


func _on_empty() -> void:
	if _cooldown > 0.0:
		return
	_cooldown = 0.25
	AudioPool.play_3d(empty_sound, global_position, AudioPool.BUS_WEAPONS)
	try_reload()


func _stat(stat_key: StringName, base_value: float) -> float:
	if stats == null:
		return base_value
	return stats.get_stat_from(stat_key, base_value)


func _emit_ammo() -> void:
	ammo_changed.emit(_ammo, _reserve)
	EventBus.ammo_changed.emit(_ammo, _reserve)
