class_name ActionTelegraph
extends ActionLeaf
## The wind-up. Every attack needs a visual and audio tell proportional to its damage
## (CLAUDE.md 5.3) - this is the single most important AI quality bar, so it is one
## reusable node rather than something each tree reimplements.
##
## Returns RUNNING for EnemyData.attack_windup seconds, then SUCCESS. Being staggered
## mid-wind-up cancels it: sustained fire interrupts attacks.

## Scales the archetype's wind-up. Heavier follow-ups should telegraph longer.
@export var windup_multiplier: float = 1.0

var _elapsed: float = 0.0
var _sound_played: bool = false


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	_elapsed = 0.0
	_sound_played = false
	var enemy := actor as Enemy
	if enemy != null:
		enemy.stop_moving()


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var enemy := actor as Enemy
	if enemy == null or enemy.data == null:
		return FAILURE
	if enemy.is_staggered():
		enemy.clear_windup()
		return FAILURE

	if not _sound_played:
		_sound_played = true
		# TELEGRAPH y no el default del bus: la preparacion es la mitad sonora del
		# aviso, y un aviso que se cae por saturacion es dano sin telegrafia.
		AudioPool.play_3d(enemy.data.windup_sound, enemy.global_position,
			AudioPool.BUS_ENEMIES, 0.0, 1.0, AudioPool.Priority.TELEGRAPH)

	var duration: float = maxf(enemy.data.attack_windup * windup_multiplier, 0.05)
	_elapsed += get_physics_process_delta_time()
	enemy.face_target(get_physics_process_delta_time(), 4.0)
	enemy.show_windup(clampf(_elapsed / duration, 0.0, 1.0))

	if _elapsed < duration:
		return RUNNING
	enemy.clear_windup()
	return SUCCESS


func interrupt(actor: Node, _blackboard: Blackboard) -> void:
	var enemy := actor as Enemy
	if enemy != null:
		enemy.clear_windup()
