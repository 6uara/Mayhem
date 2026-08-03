class_name ActionSummonAdds
extends ActionLeaf
## Spawns weak adds around the summoner. Adds are registered with WaveManager the
## same way door spawns are, so a wave cannot be declared clear while summoned adds
## are still alive.

@export var spawn_radius: float = 2.5


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var enemy := actor as Enemy
	if enemy == null or enemy.data == null or enemy.data.summon_data == null:
		return FAILURE
	if not enemy.is_attack_ready():
		return FAILURE

	for i: int in maxi(enemy.data.summon_count, 1):
		var angle: float = TAU * float(i) / float(maxi(enemy.data.summon_count, 1))
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * spawn_radius
		WaveManager.spawn_summoned(enemy.data.summon_data, enemy.global_position + offset)

	AudioPool.play_3d(enemy.data.attack_sound, enemy.global_position, AudioPool.BUS_ENEMIES)
	enemy.start_attack_cooldown()
	return SUCCESS
