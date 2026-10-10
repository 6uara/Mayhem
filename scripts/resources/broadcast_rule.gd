@tool
class_name BroadcastRule
extends Resource
## Una regla de transmision: lo que el Host cambia para una oleada, como en un
## game show. "Doble pago por headshot", "botas lunares", "el publico enloquece".
##
## Todo lo que una regla puede tocar esta aca como dato, asi que escribir una
## nueva es un `.tres` y sumarla al pozo (`BroadcastRulePool`). Dura una oleada:
## empieza con ella y se va al limpiarla o al morir.

@export var id: StringName = &""
## Lo que se anuncia, corto: entra en el cartel de la oleada.
@export var title: String = ""
## Una linea que diga que cambia. Va en el chip de la HUD durante toda la oleada.
@export var description: String = ""

@export_group("Economia")
## Multiplicador por bono de estilo, por id de KillBonusTracker. Lo que no esta,
## paga normal.
@export var bonus_multipliers: Dictionary = {}
## Multiplica la plata base de cada kill. Menos de 1 castiga la kill plana.
@export var kill_reward_multiplier: float = 1.0
## Multiplica cuanto sube el rating por kill con estilo.
@export var rating_gain_multiplier: float = 1.0

@export_group("Arena")
## Multiplica la espera entre regalos del publico. 0.5 = tira el doble.
@export var drop_interval_multiplier: float = 1.0

@export_group("Jugador")
## Modificadores de stat mientras dura la regla, aplicados como una mejora global
## que se saca al terminar la oleada.
@export var stat_modifiers: Array[StatModifier] = []


func get_bonus_multiplier(bonus_id: StringName) -> float:
	return float(bonus_multipliers.get(bonus_id, bonus_multipliers.get(String(bonus_id), 1.0)))
