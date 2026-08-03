class_name WeaponData
extends Resource
## Static definition of a weapon. All balance numbers live in the .tres instance.

@export var id: StringName = &""
@export var display_name: String = ""
@export var projectile_scene: PackedScene

@export_group("Damage")
@export var damage: float = 10.0
@export var headshot_multiplier: float = 2.0
@export var falloff_start: float = 20.0
@export var falloff_end: float = 45.0
@export var falloff_min_multiplier: float = 0.5

@export_group("Firing")
## Rounds per second.
@export var fire_rate: float = 8.0
## Projectiles emitted per trigger pull (shotgun > 1).
@export var projectiles_per_shot: int = 1
@export var projectile_speed: float = 120.0
@export var projectile_gravity: float = 0.0

@export_group("Ammo")
@export var magazine_size: int = 30
@export var reserve_ammo_max: int = 120
@export var reload_time: float = 2.0

@export_group("Recoil and spread")
@export var recoil_pattern: RecoilPattern
## Spread cone half-angle in degrees.
@export var spread_hipfire: float = 1.5
@export var spread_ads: float = 0.3
@export var spread_moving_multiplier: float = 2.0
@export var spread_airborne_multiplier: float = 3.0

@export_group("ADS")
@export var ads_fov: float = 55.0
@export var ads_transition_time: float = 0.15
@export var ads_move_speed_multiplier: float = 0.7


## Damage multiplier from distance falloff.
func get_falloff_multiplier(distance: float) -> float:
	if distance <= falloff_start or falloff_end <= falloff_start:
		return 1.0
	if distance >= falloff_end:
		return falloff_min_multiplier
	var t: float = (distance - falloff_start) / (falloff_end - falloff_start)
	return lerpf(1.0, falloff_min_multiplier, t)


## Final damage for one projectile hit.
func get_damage(distance: float, is_headshot: bool) -> float:
	var value: float = damage * get_falloff_multiplier(distance)
	if is_headshot:
		value *= headshot_multiplier
	return value


func get_shot_interval() -> float:
	return 1.0 / maxf(fire_rate, 0.001)
