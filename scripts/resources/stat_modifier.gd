class_name StatModifier
extends Resource
## A single modification to one gameplay stat.
## Aggregation order is ALWAYS: base -> all ADD -> all MULTIPLY -> OVERRIDE.
## See UpgradeManager.aggregate() - this order is unit tested and must not change.

enum Operation { ADD, MULTIPLY, OVERRIDE }

@export var stat_key: StringName = &""
@export var operation: Operation = Operation.ADD
@export var value: float = 0.0
