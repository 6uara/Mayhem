class_name UtilityData
extends Resource
## A throwable/deployable utility (stun grenade, temporary wall, slow field).

@export var id: StringName = &""
@export var display_name: String = ""
@export var scene: PackedScene
@export var cost: int = 75
@export var max_carried: int = 2
@export var cooldown: float = 6.0
@export var throw_force: float = 14.0
@export var effect_radius: float = 5.0
@export var effect_duration: float = 3.0
