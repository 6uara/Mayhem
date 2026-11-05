@tool
class_name WaveData
extends Resource
## Composition and pacing of a single wave.

@export var wave_index: int = 0
@export var spawn_groups: Array[SpawnGroup] = []
## Clear time to beat for the speed bonus, in seconds.
@export var par_time: float = 60.0
@export var completion_bonus: int = 100
@export var is_elite_wave: bool = false
## Cuanto mas duros y mas rapidos salen los enemigos de esta oleada, sobre lo que
## dice su EnemyData. Crece oleada a oleada y arranca en 1 a proposito: de las
## primeras siete runs del build, una gano sobrada y cinco no pasaron de la ola 5.
## Un aumento parejo le pegaba mas a quien ya perdia temprano.
@export var enemy_health_multiplier: float = 1.0
@export var enemy_speed_multiplier: float = 1.0


func get_total_enemy_count() -> int:
	var total: int = 0
	for group: SpawnGroup in spawn_groups:
		if group != null:
			total += group.count
	return total
