class_name ConditionPlayerInRange
extends ConditionLeaf
## Succeeds when the player is within `range_multiplier` x the archetype's attack range.
## Enemies always know where the player is (CLAUDE.md 5.3), so this is a geometry
## check, not a perception check.

## Multiplies EnemyData.attack_range. Use > 1 for "close enough to commit".
@export var range_multiplier: float = 1.0
## Set to use an absolute distance instead of the archetype's attack range.
@export var absolute_range: float = 0.0
@export var invert: bool = false


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var enemy := actor as Enemy
	if enemy == null or enemy.data == null:
		return FAILURE
	var limit: float = absolute_range if absolute_range > 0.0 \
		else enemy.data.attack_range * range_multiplier
	var in_range: bool = enemy.get_distance_to_player() <= limit
	if invert:
		in_range = not in_range
	return SUCCESS if in_range else FAILURE
