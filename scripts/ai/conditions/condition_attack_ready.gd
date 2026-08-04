class_name ConditionAttackReady
extends ConditionLeaf
## Succeeds when the archetype's attack cooldown has elapsed.


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var enemy := actor as Enemy
	if enemy == null:
		return FAILURE
	return SUCCESS if enemy.is_attack_ready() else FAILURE
