class_name ActionFlyerDive
extends ActionLeaf
## La picada del Flyer: baja, se acerca y queda al alcance de todo, y después sube.
##
## Es la ventana de compromiso del arquetipo, y sin ella el Flyer no hace ninguna
## pregunta. Un volador que sólo se mantiene lejos y tira cada 2.6s no es difícil,
## es un peaje: se resuelve por acumulación, nunca ofrece un momento en el que
## matarlo se sienta bien, y ése es exactamente el patrón de los voladores peor
## recordados del género. El Cacodemon de Doom flota igual, pero abre la boca para
## tirar, y ese instante es una promesa: si le pegás ahí, pasa algo.
##
## Lo que cambia para el jugador es la pregunta. Antes era "¿le sigo tirando?" -que
## no es una pregunta, es una tarea-. Ahora es "¿me guardo el pico de daño para
## cuando baje?", que sí se puede contestar bien o mal.
##
## Va **debajo** de la rama de disparo en el selector, y eso es deliberado: la
## picada arranca en el frame en que el disparo no está listo, o sea justo después
## de tirar, y así tiene la cadencia entera de pista libre.

## A qué altura baja. Al alcance de la escopeta, que es la mitad del punto.
@export var dive_height: float = 2.5
## A qué distancia horizontal se pone mientras dura.
@export var dive_distance: float = 6.0
@export var dive_duration: float = 1.2
@export var repath_interval: float = 0.2

var _left: float = 0.0
var _repath_timer: float = 0.0


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	_left = dive_duration
	_repath_timer = 0.0
	var enemy := actor as Enemy
	if enemy != null:
		enemy.set_flight_height_override(dive_height)


func tick(actor: Node, blackboard: Blackboard) -> int:
	var enemy := actor as Enemy
	if enemy == null or enemy.data == null or not enemy.is_flying():
		return FAILURE
	# Aturdido a mitad de picada: se corta y vuelve arriba. Es la misma ley que la
	# telegrafía -el fuego sostenido interrumpe- y acá además es la recompensa de
	# haberle acertado justo cuando estaba cerca.
	if enemy.is_staggered():
		_finish(enemy, blackboard)
		return FAILURE

	# Se re-pide en cada frame y no sólo al empezar: si algo más pisó la altura
	# mientras tanto, la picada es quien manda mientras dure.
	enemy.set_flight_height_override(dive_height)
	enemy.face_target(get_physics_process_delta_time())

	_repath_timer -= get_physics_process_delta_time()
	if _repath_timer <= 0.0:
		_repath_timer = repath_interval
		var target: Vector3 = enemy.get_target_position()
		var away: Vector3 = enemy.global_position - target
		away.y = 0.0
		if away.length_squared() < 0.01:
			away = Vector3.FORWARD
		enemy.set_move_target(target + away.normalized() * dive_distance)

	_left -= get_physics_process_delta_time()
	if _left > 0.0:
		return RUNNING
	_finish(enemy, blackboard)
	return SUCCESS


func interrupt(actor: Node, blackboard: Blackboard) -> void:
	var enemy := actor as Enemy
	if enemy != null:
		_finish(enemy, blackboard)


# Private

## Devuelve la altura de crucero y rearma el reloj de la condición. Las dos cosas
## tienen que pasar en toda salida - terminar, cortarse por stagger o que el árbol
## abandone la rama -, porque un Flyer que se queda con la altura de picada pisada
## es un Flyer que no vuelve a volar nunca.
func _finish(enemy: Enemy, blackboard: Blackboard) -> void:
	enemy.clear_flight_height_override()
	var interval: float = float(blackboard.get_value(ConditionDiveReady.INTERVAL_KEY, 8.0))
	blackboard.set_value(ConditionDiveReady.COOLDOWN_KEY, interval)
