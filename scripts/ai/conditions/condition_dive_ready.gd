class_name ConditionDiveReady
extends ConditionLeaf
## Succeeds cuando al Flyer le toca bajar a comprometerse.
##
## Vive separado de la picada misma por lo mismo que `ConditionAttackReady` vive
## separado del disparo: la cadencia es una pregunta ("¿ya?") y la acción es otra
## ("bajar"), y una secuencia reactiva vuelve a preguntar la primera en cada frame
## mientras la segunda está corriendo. Si el reloj viviera adentro de la picada, la
## picada se cortaría a sí misma en el frame siguiente al que empieza.
##
## El reloj vive en el blackboard y no acá por la otra mitad del mismo motivo: la
## picada es quien sabe cuándo terminó, así que es quien lo rearma. Un nodo publica
## el número y el otro lo consume, sin que ninguno de los dos tenga que conocer al
## otro.

## Segundos entre picadas. 8s son ~3 disparos a la cadencia del Flyer (2.6s), que
## es el ritmo que el plan de comportamiento recomienda: suficiente para que la
## picada se lea como un evento y no como su forma normal de volar.
@export var interval: float = 8.0

## Lo que le queda al reloj. Lo escribe esta condición y lo rearma la picada.
const COOLDOWN_KEY: StringName = &"flyer_dive_cooldown"
## El intervalo autorado, publicado para que la picada rearme con el mismo número
## en vez de llevar una copia propia que se desincronice en silencio.
const INTERVAL_KEY: StringName = &"flyer_dive_interval"


func tick(actor: Node, blackboard: Blackboard) -> int:
	var enemy := actor as Enemy
	if enemy == null or not enemy.is_flying():
		return FAILURE

	blackboard.set_value(INTERVAL_KEY, interval)
	# Arranca con el reloj lleno: el arquetipo se presenta volando y disparando, y
	# la picada es lo que aprende el jugador después, no lo primero que ve.
	var left: float = float(blackboard.get_value(COOLDOWN_KEY, interval))
	if left <= 0.0:
		return SUCCESS

	left -= get_physics_process_delta_time()
	blackboard.set_value(COOLDOWN_KEY, left)
	return SUCCESS if left <= 0.0 else FAILURE
