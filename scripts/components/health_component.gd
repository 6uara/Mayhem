class_name HealthComponent
extends Node
## Holds hit points for whatever owns it.
##
## Lo único que sabe del afuera es quién pegó último, y sólo porque es el único
## lugar por el que pasan todas las fuentes de daño del juego - bala, hitscan,
## explosión, charco, melee. Guardar el atacante en cada una de ellas por separado
## era garantizar que la próxima se olvidara. No interpreta al atacante: no
## pregunta si es el jugador ni de qué facción es, sólo lo anota (ver
## PLAN_NEW_ENEMY_TYPES §2.4).

signal damaged(amount: float, remaining: float)
signal healed(amount: float, remaining: float)
signal died()

@export var max_health: float = 100.0
## Multiplies incoming damage. Upgrades drive this through StatsComponent.
@export var damage_taken_multiplier: float = 1.0
@export var is_invulnerable: bool = false

var current_health: float = 0.0
var is_dead: bool = false

## Quién pegó último, o `null` si nadie se atribuyó el golpe. En el instante de
## `died` es el asesino, que es de lo que cuelga la economía.
##
## Un golpe sin atacante (la espoleta del Bomber matándose sola, un test) **no lo
## borra**: matarse no es lo mismo que cambiar de dueño, y si lo borrara, un
## Bomber al que el jugador dejó al borde de la muerte dejaría de pagarle por
## haber llegado a cero un frame antes de tiempo.
var last_attacker: Node = null

## De que vino el **ultimo** golpe, como id de DamageCause. A diferencia de
## `last_attacker`, un golpe sin atacante si lo pisa (queda en `arena`): esto
## describe el golpe, no a quien se le debe la muerte.
var last_hit_cause: StringName = &""

## Ganchos opcionales para reglas que dependen del dueño y no de la vida en si.
##
## `incoming_scale` devuelve un multiplicador extra para el golpe que entra (la
## armadura que escala con la velocidad). `death_guard` se pregunta cuando un
## golpe mataria: si devuelve true, el golpe deja la vida en 1 en vez de matar
## (el segundo aire). Los dos son del jugador; un enemigo no los usa.
var incoming_scale: Callable = Callable()
var death_guard: Callable = Callable()


func _ready() -> void:
	current_health = max_health


# Public API

## Returns the damage actually applied (0.0 when nothing landed).
##
## `attacker` es quien lo causó. Opcional a propósito: las fuentes que todavía no
## saben de quién son siguen andando igual, y lo peor que pasa es que la muerte
## quede sin dueño.
##
## `cause` nombra el origen cuando el atacante no lo dice: la explosion de un
## Bomber se atribuye a quien lo mato, pero lo que golpeo fue el Bomber.
func apply_damage(amount: float, attacker: Node = null, cause: StringName = &"") -> float:
	if is_dead or is_invulnerable or amount <= 0.0:
		return 0.0
	var scaled: float = amount * damage_taken_multiplier
	if incoming_scale.is_valid():
		scaled *= maxf(float(incoming_scale.call()), 0.0)
	var applied: float = minf(scaled, current_health)
	if applied >= current_health and death_guard.is_valid() and bool(death_guard.call()):
		applied = maxf(current_health - 1.0, 0.0)
	current_health -= applied
	if attacker != null:
		last_attacker = attacker
	last_hit_cause = cause if cause != &"" else DamageCause.of(attacker)
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
	# Pooleado: sin esto el próximo ocupante del cuerpo nace debiéndole la muerte
	# a quien mató al anterior.
	last_attacker = null
	last_hit_cause = &""
