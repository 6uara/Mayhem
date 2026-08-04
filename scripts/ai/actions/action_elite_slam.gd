class_name ActionEliteSlam
extends ActionLeaf
## The Elite's slam: melee damage plus a pool of acid left on the floor.
##
## This is what makes the Elite "area denial" rather than just a large Rusher. The
## hazard's decal radius IS its damage radius, and it warns for the same 0.6s as
## every other hazard - so the ground it takes away is honest, and the player can
## read it instantly because they have seen that stripe pattern before.

## Pool left behind, as a multiple of the Elite's attack range.
@export var pool_radius_multiplier: float = 1.6
@export var pool_duration: float = 4.0
## Fraction of the Elite's damage the pool deals per tick.
@export var pool_damage_fraction: float = 0.35
@export var hazard_scene: PackedScene


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var enemy := actor as Enemy
	if enemy == null or enemy.data == null:
		return FAILURE

	enemy.deal_melee_damage()
	_leave_pool(enemy)
	enemy.start_attack_cooldown()
	return SUCCESS


## Denies the ground the Elite just slammed, so standing still next to it stays a
## bad idea after the hit lands.
func _leave_pool(enemy: Enemy) -> void:
	if hazard_scene == null:
		return
	var hazard: Node = ObjectPool.acquire(hazard_scene)
	var zone := hazard as HazardZone
	if zone == null:
		push_error("ActionEliteSlam: hazard_scene is not a HazardZone")
		return
	zone.global_position = enemy.global_position
	zone.setup(enemy.data.damage * pool_damage_fraction,
		enemy.data.attack_range * pool_radius_multiplier, pool_duration)
