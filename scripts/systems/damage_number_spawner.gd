class_name DamageNumberSpawner
extends Node
## Pools a floating DamageNumber over whatever EventBus.damage_dealt names as
## the target - the same signal HitstopController already consumes, so this
## never becomes a second source of truth for how much damage landed.
##
## `target` on that signal carries no exact hit position, only the Node that
## was hit, so numbers spawn near the target's own origin plus `height_offset`
## rather than the precise impact point. Good enough to read as attached to
## what got hit; a new EventBus parameter for exact position was not worth it
## for a cosmetic-only number.

@export var damage_number_scene: PackedScene
## Enemy origins sit at the feet (EnemyData.head_offset etc. are all measured
## up from there) - numbers spawning at ground level would read as coming from
## the floor, not the hit.
@export var height_offset: float = 1.1


func _ready() -> void:
	EventBus.damage_dealt.connect(_on_damage_dealt)


func _on_damage_dealt(target: Node, amount: float, is_headshot: bool) -> void:
	if amount <= 0.0 or damage_number_scene == null:
		return
	if not bool(SettingsManager.get_value("hud/damage_numbers", true)):
		return
	var target_3d: Node3D = target as Node3D
	if target_3d == null:
		return
	var number: Node = ObjectPool.acquire(damage_number_scene)
	if number == null or not number.has_method(&"play_at"):
		return
	number.call(&"play_at", target_3d.global_position + Vector3.UP * height_offset,
		amount, is_headshot)
