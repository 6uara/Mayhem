class_name EnemyData
extends Resource
## Static definition of an enemy archetype.

enum Archetype { RUSHER, RANGER, ELITE, HEALER, SUMMONER }

@export var id: StringName = &""
@export var display_name: String = ""
@export var archetype: Archetype = Archetype.RUSHER
@export var scene: PackedScene
@export var behavior_tree: PackedScene

@export_group("Stats")
@export var max_health: float = 100.0
@export var move_speed: float = 5.0
@export var damage: float = 10.0
@export var attack_range: float = 2.0
@export var attack_cooldown: float = 1.5
@export var mass: float = 1.0
@export var stagger_resistance: float = 0.0

@export_group("Economy")
@export var reward_currency: int = 10
