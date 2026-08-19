class_name ActionLeapAttack
extends ActionLeaf
## El salto del melee: se tira encima del jugador y pega solo si lo alcanza.
##
## Reemplaza al golpe parado de ActionMeleeAttack para los arquetipos que saben
## saltar. La diferencia no es el daño sino de que se trata el cuerpo a cuerpo: el
## golpe de antes aparecia cuando el enemigo ya te habia alcanzado y no habia
## mucho que hacer al respecto, y esto es un compromiso que se lee durante la
## telegrafia, se ve venir en el aire y se esquiva moviendose.
##
## Va despues de ActionTelegraph en el arbol, que es el que pone la preparacion.
## Devuelve RUNNING todo el vuelo y la recuperacion, asi que el arbol no vuelve a
## pedir nada hasta que el enemigo termino de aterrizar.
##
## Si el salto no sale - sin piso, fuera de alcance, una pared en el medio -
## devuelve FAILURE y el arbol cae a la rama de perseguir, que es lo correcto: el
## enemigo se acerca mas y lo intenta de nuevo.

var _launched: bool = false


func before_run(_actor: Node, _blackboard: Blackboard) -> void:
	_launched = false


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var enemy := actor as Enemy
	if enemy == null:
		return FAILURE

	if not _launched:
		if not enemy.start_leap():
			return FAILURE
		_launched = true
		# El cooldown arranca al despegar y no al aterrizar: si no, la
		# recuperacion se sumaria a la espera y el arquetipo atacaria bastante
		# menos seguido de lo que dice su attack_cooldown.
		enemy.start_attack_cooldown()
		return RUNNING

	if enemy.is_leaping() or enemy.is_recovering():
		return RUNNING
	return SUCCESS
