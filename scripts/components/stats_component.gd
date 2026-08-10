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
