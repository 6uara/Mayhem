class_name ActionRangedAttack
extends ActionLeaf
## Fires a projectile at the player and starts the cooldown.


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var enemy := actor as Enemy
	if enemy == null:
		return FAILURE
	enemy.fire_projectile()
	enemy.start_attack_cooldown()
	return SUCCESS
