class_name ActionKeepDistance
extends ActionLeaf
## Kiting: holds `preferred_distance` from the player, backing off when crowded and
## closing when too far. Rangers and healers use this to punish standing still
## without ever becoming melee.

## Tolerance band around preferred_distance, so the enemy does not jitter.
@export var tolerance: float = 2.0
@export var repath_interval: float = 0.2
## Cuanto se tiene que haber corrido el destino para que valga la pena repathear.
##
## Es la perilla que hace pagable el puesto asignado. El punto al que camina un
## enemigo con rumbo se mueve con el jugador **y** con hacia donde mira el
## jugador, asi que a intervalo fijo se repathea siempre, aunque el destino se
## haya corrido diez centimetros - y un repath no es gratis: `set_move_target()`
## consulta el NavigationServer para bajar el punto al navmesh, y despues el
## agente recalcula el camino entero.
##
## Medido: con los tiradores pidiendo rumbo y sin esta guarda, la oleada 10
## completa cayo de 40 a 23 FPS. Con la guarda vuelve, y de paso se ve mejor: el
## tirador se planta en su puesto en vez de corregirlo cinco veces por segundo.
@export var repath_tolerance: float = 2.0


var _repath_timer: float = 0.0


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var enemy := actor as Enemy
	if enemy == null or enemy.data == null:
		return FAILURE
	var preferred: float = enemy.data.preferred_distance
	if preferred <= 0.0:
		return FAILURE

	var distance: float = enemy.get_distance_to_target()
	enemy.face_target(get_physics_process_delta_time())

	# Estar a la distancia justa no sirve de nada si hay una columna en el medio.
	# Este SUCCESS era el que dejaba al tirador plantado detras de una pared el
	# resto de la ola: devolvia "ya estoy donde quiero", el selector no llegaba
	# nunca a la rama de acercarse, y nadie lo movia de ahi. Sin vision la
	# distancia preferida deja de ser el objetivo y lo que se busca es el angulo.
	if not enemy.has_line_of_sight_to_target():
		return _reposition(enemy, enemy.get_target_position())

	if absf(distance - preferred) <= tolerance:
		enemy.stop_moving()
		return SUCCESS

	var player_position: Vector3 = enemy.get_target_position()
	var away: Vector3 = enemy.global_position - player_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3.FORWARD
	return _reposition(enemy, player_position + away.normalized() * preferred)


## Camina hacia `wanted` respetando el intervalo, la tolerancia y el presupuesto de
## repath. Es el cuerpo que comparten el kiteo y el destrabe por falta de vision, y
## esta aparte para que los dos paguen los mismos frenos: sin eso el tirador ciego
## pediria un camino nuevo todos los frames.
func _reposition(enemy: Enemy, wanted: Vector3) -> int:
	_repath_timer -= get_physics_process_delta_time()
	if _repath_timer <= 0.0:
		_repath_timer = repath_interval
		var moved: float = wanted.distance_squared_to(enemy.move_target)
		if (not enemy.is_moving or moved > repath_tolerance * repath_tolerance) \
				and CombatDirector.request_repath(enemy):
			enemy.set_move_target(wanted)
	return RUNNING


func before_run(_actor: Node, _blackboard: Blackboard) -> void:
	_repath_timer = 0.0
