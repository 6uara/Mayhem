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


func get_total_enemy_count() -> int:
	var total: int = 0
	for group: SpawnGroup in spawn_groups:
		if group != null:
			total += group.count
	return total
