class_name ActionArmFuse
extends ActionLeaf
## Prende la espoleta del Bomber, una sola vez, y despues se corre del camino.
##
## Es la hoja mas corta del juego porque tiene que serlo: una vez armada, la
## cuenta no la lleva el arbol sino Enemy._tick_fuse(), que corre aunque el bicho
## este aturdido, en el aire o sin objetivo. Un ataque se puede interrumpir; una
## espoleta no, y por eso no puede vivir en una rama que el arbol pueda abandonar.
##
## Devuelve SUCCESS unicamente en el frame en que arma. De ahi en mas devuelve
## FAILURE a proposito, para que el selector caiga a la rama de perseguir: una
## bomba armada que se queda quieta le regala al jugador la unica decision que el
## arquetipo le pide tomar. Tiene que seguir viniendo.

## Contra que se telegrafia el armado, ademas del anillo y el parpadeo del cuerpo:
## el destello puntual de "acabo de armarme". 0 lo apaga.
@export var arm_flash: float = 1.0


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var enemy := actor as Enemy
	if enemy == null:
		return FAILURE
	if not enemy.arm_fuse():
		return FAILURE
	if arm_flash > 0.0:
		enemy.show_windup(arm_flash)
	return SUCCESS
