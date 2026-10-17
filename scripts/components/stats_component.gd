class_name StatsComponent
extends Node
## Aggregates UpgradeManager modifiers into live values for the node that owns it.
## Base values are authored here; every purchased upgrade layers on top.

## Canonical stat keys. UpgradeData.stat_modifiers must use these exact names.
const MOVE_SPEED: StringName = &"move_speed"
const JUMP_VELOCITY: StringName = &"jump_velocity"
const AIR_CONTROL: StringName = &"air_control"
const DASH_CHARGES: StringName = &"dash_charges"
const DASH_COOLDOWN: StringName = &"dash_cooldown"
const GRAPPLE_RANGE: StringName = &"grapple_range"
const GRAPPLE_COOLDOWN: StringName = &"grapple_cooldown"
const GRAPPLE_AIM_ASSIST: StringName = &"grapple_aim_assist"
const MAX_HEALTH: StringName = &"max_health"
const DAMAGE_TAKEN_MULTIPLIER: StringName = &"damage_taken_multiplier"
const WEAPON_DAMAGE: StringName = &"weapon_damage"
const FIRE_RATE: StringName = &"fire_rate"
const MAGAZINE_SIZE: StringName = &"magazine_size"
const RESERVE_AMMO_MAX: StringName = &"reserve_ammo_max"
const RELOAD_TIME: StringName = &"reload_time"
const RECOIL_MAGNITUDE: StringName = &"recoil_magnitude"
const SPREAD_MULTIPLIER: StringName = &"spread_multiplier"
const ADS_TRANSITION_TIME: StringName = &"ads_transition_time"
## Vida por segundo. Base 0: sin la mejora, el jugador no se regenera.
const HEALTH_REGEN: StringName = &"health_regen"

## Mejoras raras. Todas tienen base neutra (0, o 1 en los multiplicadores), asi
## que la regla esta apagada hasta que una mejora la mueve: una mejora rara sigue
## siendo "solo StatModifiers", como pide UpgradeData.
const SLIDE_RELOAD_RATE: StringName = &"slide_reload_rate"
const DASH_RAM_DAMAGE: StringName = &"dash_ram_damage"
const AIRBORNE_DAMAGE_MULTIPLIER: StringName = &"airborne_damage_multiplier"
const HEADSHOT_KILL_REFUND: StringName = &"headshot_kill_refund"
const SPEED_DAMAGE_REDUCTION: StringName = &"speed_damage_reduction"
const STYLE_PAYOUT_MULTIPLIER: StringName = &"style_payout_multiplier"
const SECOND_WIND_CHARGES: StringName = &"second_wind_charges"
const PAD_DASH_REFILL: StringName = &"pad_dash_refill"

## Mejoras raras de un arma y attachments. Por arma (se piden con el id del arma,
## como el resto de los stats de arma), y con base en WeaponData o neutra.
const PIERCE_COUNT: StringName = &"pierce_count"
const SPLASH_RADIUS: StringName = &"splash_radius"
const SELF_KNOCKBACK: StringName = &"self_knockback"
const PROJECTILES_PER_SHOT: StringName = &"projectiles_per_shot"
## Multiplica el daño de la ultima bala del cargador. Base 1.
const LAST_ROUND_DAMAGE: StringName = &"last_round_damage"
## Multiplica el daño del primer tiro de una rafaga (con el patron de recoil en
## cero). Base 1.
const FIRST_SHOT_DAMAGE: StringName = &"first_shot_damage"
## Multiplica la penalidad de dispersion por moverse o estar en el aire: 0 la
## borra. Base 1.
const MOVING_SPREAD_PENALTY: StringName = &"moving_spread_penalty"

signal stats_changed()

## stat_key -> base value, authored per owner.
@export var base_values: Dictionary = {}

var _cache: Dictionary = {}


func _ready() -> void:
	UpgradeManager.upgrades_changed.connect(_on_upgrades_changed)


# Public API

## Live value for `stat_key`, with all owned upgrades applied. Cached until
## the upgrade set changes, so this is safe to call per frame.
func get_stat(stat_key: StringName, fallback: float = 0.0) -> float:
	if _cache.has(stat_key):
		return _cache[stat_key]
	var base_value: float = float(base_values.get(stat_key, fallback))
	var value: float = UpgradeManager.get_stat(stat_key, base_value)
	_cache[stat_key] = value
	return value


## Reads the base from `data` rather than `base_values` - lets a weapon's own
## resource supply the base while upgrades still apply. Never cached (unlike
## `get_stat()`): a weapon-scoped value depends on which weapon is asking, so
## caching it here by `stat_key` alone would hand another weapon a stale answer.
func get_stat_from(stat_key: StringName, base_value: float,
		weapon_id: StringName = &"") -> float:
	return UpgradeManager.get_stat(stat_key, base_value, weapon_id)


func set_base(stat_key: StringName, value: float) -> void:
	base_values[stat_key] = value
	_cache.erase(stat_key)
	stats_changed.emit()


func invalidate() -> void:
	_cache.clear()
	stats_changed.emit()


# Private

func _on_upgrades_changed() -> void:
	invalidate()
