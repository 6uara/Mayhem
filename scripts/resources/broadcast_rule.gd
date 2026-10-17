@tool
class_name BroadcastRule
extends Resource
## Una regla de transmision: lo que el Host cambia para una oleada, como en un
## game show. "Doble pago por headshot", "botas lunares", "el publico enloquece".
##
## Todo lo que una regla puede tocar esta aca como dato, asi que escribir una
## nueva es un `.tres` y sumarla al pozo (`BroadcastRulePool`). Dura una oleada:
## empieza con ella y se va al limpiarla o al morir.
##
## Un **contrato** es la misma cosa con un precio: una restriccion que el jugador
## elige firmar en la tienda a cambio de `contract_payout` al limpiar la oleada.
## Lo que lo vuelve contrato es tener pago; el resto de los campos funciona igual.

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
## Cada kill deja un charco que quema a todos -jugador y horda- durante
## `kill_hazard_duration`. 0 lo apaga. Es "el piso arde": matar cerca de uno
## mismo pasa a ser una decision de posicion.
@export var kill_hazard_damage: float = 0.0
@export var kill_hazard_radius: float = 2.5
@export var kill_hazard_duration: float = 4.0

@export_group("Enemigos")
## Cambios a los enemigos que aparezcan mientras dura la regla.
@export var enemy_modifiers: Array[EnemyRuleModifier] = []
## Cacería: uno de cada `mark_every` enemigos sale marcado, hasta `mark_limit`
## por oleada. Matar uno marcado paga el bono `marked`. 0 lo apaga.
@export var mark_every: int = 0
@export var mark_limit: int = 0

@export_group("Jugador")
## Modificadores de stat mientras dura la regla, aplicados como una mejora global
## que se saca al terminar la oleada.
@export var stat_modifiers: Array[StatModifier] = []

@export_group("Contrato")
## Plata al limpiar la oleada con el contrato firmado. Mayor que cero vuelve a la
## regla un contrato.
@export var contract_payout: int = 0
## Cuanto se suma al pago por cada oleada (1-based): el mismo contrato vale mas
## cuando la oleada es mas dura.
@export var contract_payout_per_wave: int = 0


func get_bonus_multiplier(bonus_id: StringName) -> float:
	return float(bonus_multipliers.get(bonus_id, bonus_multipliers.get(String(bonus_id), 1.0)))


func is_contract() -> bool:
	return contract_payout > 0


## El pago por limpiar la oleada `wave_index` (0-based) con este contrato.
func get_contract_payout(wave_index: int) -> int:
	if not is_contract():
		return 0
	return contract_payout + contract_payout_per_wave * (maxi(wave_index, 0) + 1)


## Los multiplicadores de vida, velocidad y daño para el arquetipo `enemy_id`,
## como `Vector3(vida, velocidad, daño)`.
func get_enemy_multipliers(enemy_id: StringName) -> Vector3:
	var result := Vector3.ONE
	for modifier: EnemyRuleModifier in enemy_modifiers:
		if modifier != null and modifier.applies_to(enemy_id):
			result *= Vector3(modifier.health_multiplier, modifier.speed_multiplier,
				modifier.damage_multiplier)
	return result
