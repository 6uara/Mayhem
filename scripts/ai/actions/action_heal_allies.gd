class_name ActionHealAllies
extends ActionLeaf
## Pulses healing to nearby wounded enemies. Fails when nobody needs it, so the
## healer's tree falls through to repositioning instead of standing still.
##
## The tether visual that makes the healer an obvious priority target is driven by
## HealerTether, which reads the same radius.


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var enemy := actor as Enemy
	if enemy == null or enemy.data == null:
		return FAILURE
	if not enemy.is_attack_ready():
		return FAILURE
	var healed: int = enemy.heal_nearby_allies()
	if healed <= 0:
		return FAILURE
	AudioPool.play_3d(enemy.data.attack_sound, enemy.global_position, AudioPool.BUS_ENEMIES)
	enemy.start_attack_cooldown()
	return SUCCESS
