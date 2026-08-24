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

## Cuantas espoletas pueden estar contando a la vez en todo el arena.
##
## Tope por rol y no por cantidad: lo que satura no es cuantos enemigos hay sino
## cuantos piden lo mismo al mismo tiempo. Dos explosiones simultaneas son la
## muerte sin decision de por medio, y una tercera cuenta regresiva no agrega
## ninguna pregunta nueva - solo tapa a las otras dos. El que no arma sigue
## viniendo, asi que armara en cuanto se libere un lugar.
@export var max_armed: int = 2


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var enemy := actor as Enemy
	if enemy == null:
		return FAILURE
	if max_armed > 0 and _armed_count() >= max_armed:
		return FAILURE
	if not enemy.arm_fuse():
		return FAILURE
	if arm_flash > 0.0:
		enemy.show_windup(arm_flash)
	return SUCCESS


## Cuantos hay contando ahora mismo. Recorre la lista de vivos que `Enemy` ya
## mantiene -no el grupo del arbol, que arma un Array nuevo en cada llamada- y
## solo corre cuando un Bomber esta por armar, o sea unas pocas veces por ola.
func _armed_count() -> int:
	var armed: int = 0
	for other: Enemy in Enemy.get_active_enemies():
		if is_instance_valid(other) and other.is_active and other.is_fuse_armed():
			armed += 1
	return armed
