class_name HealthComponent
extends Node
## Holds hit points for whatever owns it. Knows nothing about who dealt the damage.

signal damaged(amount: float, remaining: float)
signal healed(amount: float, remaining: float)
signal died()

@export var max_health: float = 100.0
## Multiplies incoming damage. Upgrades drive this through StatsComponent.
@export var damage_taken_multiplier: float = 1.0
@export var is_invulnerable: bool = false

var current_health: float = 0.0
var is_dead: bool = false


func _ready() -> void:
	current_health = max_health


# Public API

## Returns the damage actually applied (0.0 when nothing landed).
func apply_damage(amount: float) -> float:
	if is_dead or is_invulnerable or amount <= 0.0:
		return 0.0
	var applied: float = minf(amount * damage_taken_multiplier, current_health)
	current_health -= applied
	damaged.emit(applied, current_health)
	if current_health <= 0.0:
		is_dead = true
		died.emit()
	return applied


func heal(amount: float) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	var applied: float = minf(amount, max_health - current_health)
	current_health += applied
	if applied > 0.0:
		healed.emit(applied, current_health)
	return applied


## Changes max health while preserving the current health fraction.
func set_max_health(value: float, keep_ratio: bool = true) -> void:
	var ratio: float = get_health_fraction()
	max_health = maxf(value, 1.0)
	current_health = max_health * ratio if keep_ratio else minf(current_health, max_health)


func get_health_fraction() -> float:
	if max_health <= 0.0:
		return 0.0
	return current_health / max_health


func reset() -> void:
	current_health = max_health
	is_dead = false
