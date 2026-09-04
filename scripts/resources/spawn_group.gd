@tool
class_name SpawnGroup
extends Resource
## One batch of enemies emitted from a set of spawn doors during a wave.

@export var enemy_data: EnemyData
@export var count: int = 1
@export var spawn_door_ids: Array[StringName] = []
## Seconds after wave start before this group begins spawning.
@export var delay: float = 0.0
## Seconds between individual spawns within the group.
@export var interval: float = 0.5


## Total seconds from wave start until this group has finished spawning.
func get_total_duration() -> float:
	return delay + maxf(float(count - 1), 0.0) * interval
