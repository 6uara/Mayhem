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


## El arbol puede abandonar la rama a mitad de vuelo - un aturdimiento, un cambio
## de objetivo. La ficha se devuelve igual, o el cupo del rol se agota con
## enemigos que ya no estan saltando.
func after_run(actor: Node, _blackboard: Blackboard) -> void:
	CombatDirector.release_attack_token(actor as Enemy)


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var enemy := actor as Enemy
	if enemy == null:
		return FAILURE

	if not _launched:
		# El salto es el ataque que se lee, asi que es el que tiene techo. Con
		# quince Rushers encima, quince saltos simultaneos no son quince
		# amenazas: son una pared que aparece de golpe y no se puede leer ni
		# esquivar. El que no consigue ficha sigue presionando desde donde esta y
		# vuelve a pedirla al proximo ciclo del arbol.
		if not CombatDirector.request_attack_token(enemy):
			return FAILURE
		if not enemy.start_leap():
			CombatDirector.release_attack_token(enemy)
			return FAILURE
		_launched = true
		# El cooldown arranca al despegar y no al aterrizar: si no, la
		# recuperacion se sumaria a la espera y el arquetipo atacaria bastante
		# menos seguido de lo que dice su attack_cooldown.
		enemy.start_attack_cooldown()
		return RUNNING

	if enemy.is_leaping() or enemy.is_recovering():
		return RUNNING
	# Recien al terminar la recuperacion, no al aterrizar: mientras esta juntando
	# las patas sigue ocupando el espacio delante del jugador.
	CombatDirector.release_attack_token(enemy)
	return SUCCESS
