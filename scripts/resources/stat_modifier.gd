class_name StatModifier
extends Resource
## A single modification to one gameplay stat.
## Aggregation order is ALWAYS: base -> all ADD -> all MULTIPLY -> OVERRIDE.
## See UpgradeManager.aggregate() - this order is unit tested and must not change.

enum Operation { ADD, MULTIPLY, OVERRIDE }

@export var stat_key: StringName = &""
@export var operation: Operation = Operation.ADD
@export var value: float = 0.0
## Si no esta vacio, el modificador cuenta una vez por cada stack de una mejora
## con esta etiqueta que tenga el build (UpgradeData.tags), en vez de una vez. Asi
## escalan las raras de sinergia sin dejar de ser "solo StatModifiers": el orden
## de agregacion no cambia, solo cuantas copias del modificador entran.
@export var per_tag: StringName = &""
## Este modificador escalado es el precio y no el premio (el -6 de vida por
## mejora de armadura del Streamliner). Solo lo lee la tienda, para decir si una
## oferta alimenta una rara o le cobra.
@export var per_tag_is_penalty: bool = false
