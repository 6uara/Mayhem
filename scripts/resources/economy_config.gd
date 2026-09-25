@tool
class_name EconomyConfig
extends Resource
## The single source of economy tuning. All payout numbers live in one .tres.

## Reward per kill, keyed by EnemyData.Archetype index.
@export var kill_reward_rusher: int = 10
@export var kill_reward_ranger: int = 14
@export var kill_reward_elite: int = 60
@export var kill_reward_healer: int = 20
@export var kill_reward_summoner: int = 25

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

@export_group("Global")
@export var currency_multiplier: float = 1.0
@export var starting_currency: int = 0


func get_kill_reward(archetype: EnemyData.Archetype) -> int:
	match archetype:
		EnemyData.Archetype.RUSHER: return kill_reward_rusher
		EnemyData.Archetype.RANGER: return kill_reward_ranger
		EnemyData.Archetype.ELITE: return kill_reward_elite
		EnemyData.Archetype.HEALER: return kill_reward_healer
		EnemyData.Archetype.SUMMONER: return kill_reward_summoner
	return 0


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
