class_name ActionRangedAttack
extends ActionLeaf
## Fires a projectile at the player and starts the cooldown.
##
## Sin linea de vision no dispara. La rama ya deberia haberse cerrado antes -para
## eso esta `ConditionPlayerInRange.require_line_of_sight`, que la cierra **antes**
## del telegrafo en vez de tirar el aviso a la basura-, y esto es la red: un arbol
## nuevo que se olvide de pedirla no va a hacer que un enemigo le dispare a una
## columna hasta que termine la ola.


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var enemy := actor as Enemy
	if enemy == null:
		return FAILURE
	if not enemy.has_line_of_sight_to_target():
		return FAILURE
	enemy.fire_projectile()
	# Lo que dispara el clip "attack" del modelo: el retroceso del cañon en el
	# instante del tiro. Despues del chequeo de linea de vision: sin tiro no hay
	# retroceso.
	enemy.ability_used.emit()
	enemy.start_attack_cooldown()
	return SUCCESS
