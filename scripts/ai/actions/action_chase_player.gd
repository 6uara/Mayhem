class_name ActionChasePlayer
extends ActionLeaf
## Walks toward the player, returning RUNNING until inside `stop_at` x attack range.
##
## The distance that ends the chase is measured to the player, not to the point
## being walked to: the lane the enemy approaches on is a detour, and it must not
## be able to stop short of the player by being at the end of it.

@export var stop_at_range_multiplier: float = 0.9
## Re-path interval. The player moves fast, but re-pathing every frame is wasteful.
@export var repath_interval: float = 0.2

var _repath_timer: float = 0.0


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var enemy := actor as Enemy
	if enemy == null or enemy.data == null:
		return FAILURE

	if enemy.get_distance_to_player() <= enemy.data.attack_range * stop_at_range_multiplier:
		enemy.stop_moving()
		return SUCCESS

	_repath_timer -= get_physics_process_delta_time()
	if _repath_timer <= 0.0:
		_repath_timer = repath_interval
		# Not the player's feet: a lane beside them, personal to this enemy, that
		# closes as it arrives. See Enemy.get_approach_position - a pack that all
		# paths to one point walks in single file.
		enemy.set_move_target(enemy.get_approach_position())
	enemy.face_player(get_physics_process_delta_time())
	return RUNNING


func before_run(_actor: Node, _blackboard: Blackboard) -> void:
	_repath_timer = 0.0
