@tool
class_name EconomyConfig
extends Resource
## The single source of economy tuning. All payout numbers live in one .tres.
##
## What a kill pays is not here: it is `EnemyData.reward_currency`, per archetype.
## There used to be a second copy of those numbers in this file that only the
## balance editor read, and it did not know half the cast.

@export_group("Bonuses")
@export var no_damage_bonus: int = 100
## Fractions of par_time. A clear at or under tier i pays speed_bonus_payouts[i].
## Must be ascending and the same length as `speed_bonus_payouts`.
@export var speed_bonus_tiers: PackedFloat32Array = PackedFloat32Array([0.5, 0.75, 1.0])
@export var speed_bonus_payouts: PackedInt32Array = PackedInt32Array([150, 100, 50])

@export_group("Kill bonuses")
## Recargo por kill, por id de KillBonusTracker.Bonus. Viven aca y no en el
## tracker porque esto sigue siendo "el unico lugar donde se tocan los numeros
## de la economia" - el tracker decide **si** se cumple un bono, nunca cuanto
## vale.
@export var bonus_headshot: int = 10
@export var bonus_airborne: int = 15
@export var bonus_spin: int = 40
@export var bonus_grapple: int = 20
@export var bonus_dash: int = 15
@export var bonus_long_shot: int = 25
@export var bonus_point_blank: int = 10
@export var bonus_last_round: int = 20
@export var bonus_double: int = 15
@export var bonus_triple: int = 35
@export var bonus_mayhem: int = 75
## Matar al Healer mientras sostiene a la oleada. Caro a proposito: es la unica
## decision de objetivo que el juego pide de verdad.
@export var bonus_priority: int = 30
## Matar un enemigo marcado por la regla de Cacería. Alto a proposito: es una
## recompensa por ir a buscar a uno en particular en medio de la horda.
@export var bonus_marked: int = 60

@export_group("Damage penalty")
## Monedas perdidas por punto de daño recibido.
##
## El daño ya costaba vida y el bono de oleada limpia; esto lo hace costar
## tambien lo que el jugador estaba por gastar, que es lo que convierte a
## "esquivar" en una decision economica y no solo en una de supervivencia.
## Cero lo apaga entero.
@export var currency_loss_per_damage: float = 1.0
## Tope por golpe, para que un unico impacto de Elite no vacie la billetera y
## deje la tienda sin sentido. Cero significa sin tope.
@export var currency_loss_max_per_hit: int = 40

@export_group("Score")
## El puntaje es kills + estilo + oleadas, nunca tiempo ni plata en mano.
##
## Antes era plata guardada x10 mas un bono por terminar rapido, y eso premiaba
## morir: una muerte a los 30s sumaba casi todo el bono de tiempo, y gastar en la
## tienda bajaba el puntaje. Ahora todo lo que suma se gano jugando, y morir solo
## corta lo que se iba a seguir sumando.
##
## Puntos por cada moneda de recompensa base de una kill.
@export var score_per_kill_reward: int = 10
## Puntos por cada moneda de bono de estilo. El rating de la transmision lo
## multiplica, igual que a la plata.
@export var score_per_style: int = 10
## Puntos por limpiar la oleada N: esto por N. Escala con la oleada porque la
## decima vale mas que la primera.
@export var score_per_wave: int = 500
## Lo que suma ganar la run entera, ademas de la ultima oleada.
@export var score_victory_bonus: int = 5000

@export_group("Global")
@export var currency_multiplier: float = 1.0
@export var starting_currency: int = 0


## Payout for clearing a wave in `duration` seconds against `par_time`.
## Returns 0 when no tier is met.
func get_speed_bonus(duration: float, par_time: float) -> int:
	if par_time <= 0.0:
		return 0
	var ratio: float = duration / par_time
	var tier_count: int = mini(speed_bonus_tiers.size(), speed_bonus_payouts.size())
	for i: int in tier_count:
		if ratio <= speed_bonus_tiers[i]:
			return speed_bonus_payouts[i]
	return 0


## Lo que paga un bono de kill, o 0 si el id no es uno. Un solo lugar traduce
## id -> plata, asi que agregar un bono es tocar esta tabla y nada mas.
func get_kill_bonus(bonus_id: StringName) -> int:
	match bonus_id:
		&"headshot": return bonus_headshot
		&"airborne": return bonus_airborne
		&"spin": return bonus_spin
		&"grapple": return bonus_grapple
		&"dash": return bonus_dash
		&"long_shot": return bonus_long_shot
		&"point_blank": return bonus_point_blank
		&"last_round": return bonus_last_round
		&"double": return bonus_double
		&"triple": return bonus_triple
		&"mayhem": return bonus_mayhem
		&"priority": return bonus_priority
		&"marked": return bonus_marked
	return 0


## Lo que cuesta recibir `damage` puntos de daño, ya topeado. Devuelve 0 cuando
## la penalidad esta apagada.
func get_damage_penalty(damage: float) -> int:
	if currency_loss_per_damage <= 0.0 or damage <= 0.0:
		return 0
	var loss: int = int(round(damage * currency_loss_per_damage))
	if currency_loss_max_per_hit > 0:
		loss = mini(loss, currency_loss_max_per_hit)
	return maxi(loss, 0)
