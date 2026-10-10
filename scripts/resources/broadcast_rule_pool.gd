@tool
class_name BroadcastRulePool
extends Resource
## Las reglas de transmision que el Host puede sortear, y desde cuando.

@export var rules: Array[BroadcastRule] = []
## Primera oleada (1-based) que puede traer una regla. Las primeras se juegan
## limpias: primero se aprende el juego, despues se lo cambia.
@export var from_wave: int = 3
## Las oleadas elite se juegan sin regla: ya son el pico de la tanda.
@export var skip_elite_waves: bool = true
