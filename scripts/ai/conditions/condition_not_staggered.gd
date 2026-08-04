class_name ConditionNotStaggered
extends ConditionLeaf
## Fails while the enemy is reeling from a hit, so wind-ups get interrupted by
## sustained fire. This is what makes shooting an attacking enemy feel like it
## accomplished something.


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var enemy := actor as Enemy
	if enemy == null:
		return FAILURE
	return FAILURE if enemy.is_staggered() else SUCCESS
