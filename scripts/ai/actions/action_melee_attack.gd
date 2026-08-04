class_name ActionMeleeAttack
extends ActionLeaf
## Lands the melee hit and starts the cooldown. The damage check happens in
## Enemy.deal_melee_damage(), which misses if the player left the wind-up window -
## dodging a telegraphed attack has to actually work.


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var enemy := actor as Enemy
	if enemy == null:
		return FAILURE
	enemy.deal_melee_damage()
	enemy.start_attack_cooldown()
	return SUCCESS
