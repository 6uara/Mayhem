class_name ActionChasePlayer
extends ActionLeaf
## Walks toward the player, returning RUNNING until inside `stop_at` x attack range.
##
## The distance that ends the chase is measured to the player, not to the point
## being walked to: the lane the enemy approaches on is a detour, and it must not
## be able to stop short of the player by being at the end of it.

@export var stop_at_range_multiplier: float = 0.9
## Re-path interval. The player moves fast, but re-pathing every frame is wasteful.
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
@export var repath_tolerance: float = 1.5


var _repath_timer: float = 0.0


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var enemy := actor as Enemy
	if enemy == null or enemy.data == null:
		return FAILURE

	if enemy.get_distance_to_target() <= enemy.data.attack_range * stop_at_range_multiplier:
		enemy.stop_moving()
		return SUCCESS

	_repath_timer -= get_physics_process_delta_time()
	if _repath_timer <= 0.0:
		_repath_timer = repath_interval
		# Not the player's feet: a lane beside them, personal to this enemy, that
		# closes as it arrives. See Enemy.get_approach_position - a pack that all
		# paths to one point walks in single file, y ahora tambien el puesto que
		# le reparte el CombatDirector.
		var wanted: Vector3 = enemy.get_approach_position()
		if _worth_repathing(enemy, wanted) and CombatDirector.request_repath():
			enemy.set_move_target(wanted)
	enemy.face_target(get_physics_process_delta_time())
	return RUNNING


## Si el destino se corrio lo suficiente. Y, si se corrio, si hay turno este
## frame: un repath es una consulta al NavigationServer, y con una horda grande se
## apilan todas en los mismos frames si nadie las reparte. El que no consigue
## turno reintenta al siguiente, o sea 16ms tarde sobre un intervalo de 200ms.
func _worth_repathing(enemy: Enemy, wanted: Vector3) -> bool:
	if not enemy.is_moving:
		return true
	return wanted.distance_squared_to(enemy.move_target) > repath_tolerance * repath_tolerance


func before_run(_actor: Node, _blackboard: Blackboard) -> void:
	_repath_timer = 0.0
