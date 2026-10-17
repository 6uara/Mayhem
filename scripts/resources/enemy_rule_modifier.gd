@tool
class_name EnemyRuleModifier
extends Resource
## Lo que una regla de transmision le cambia a los enemigos que aparecen mientras
## dura: mas vida, mas velocidad, mas daño. Por arquetipo, o a todos.
##
## Se aplica al salir del pool (`Enemy.setup()`), no a los que ya estaban vivos:
## la regla arranca con la oleada, antes del primer spawn, asi que en la practica
## los alcanza a todos, y un enemigo no cambia de reglas a mitad de pelea.

## El id del arquetipo (`EnemyData.id`). Vacio: todos.
@export var enemy_id: StringName = &""
@export var health_multiplier: float = 1.0
@export var speed_multiplier: float = 1.0
@export var damage_multiplier: float = 1.0


func applies_to(id: StringName) -> bool:
	return enemy_id == &"" or enemy_id == id
