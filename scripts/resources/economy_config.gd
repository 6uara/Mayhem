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
