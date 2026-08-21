class_name ActionThrowFlask
extends ActionLeaf
## Lanza un frasco en parábola al piso donde está el jugador. Donde cae queda un
## charco que niega ese terreno.
##
## El arquetipo no apunta al jugador: apunta al suelo bajo sus pies. Errar no es
## el fracaso -es el modo normal de funcionar-, porque lo que hace es sacarte de
## donde estás parado, no pegarte. Un Environmental que acierta y uno que erra por
## poco te obligan a moverte igual, y esa es toda la diferencia con el Ranger.
##
## Vive todo acá y no en `Enemy` a propósito, siguiendo a `ActionEliteSlam`: la
## hoja se ocupa de su propio `ObjectPool` y de sus propios números. Además evita
## un ciclo - `EnemyFlask` hereda de `ThrownUtility`, que nombra a `Enemy`, así que
## si `enemy.gd` nombrara al frasco el compilador tendría que resolver un círculo,
## y a veces no puede (ver el comentario en `Explosion._victims()`).

@export var flask_scene: PackedScene
## Cuánto tarda el frasco en llegar. Es la ventana que tiene el jugador para
## salirse del círculo antes de que el charco exista, así que va larga: el arco
## es la telegrafía, y un arco rápido no se lee.
@export var flight_time: float = 1.1
@export var pool_radius: float = 3.2
@export var pool_duration: float = 5.0
## Fracción del daño del arquetipo que hace el charco por tick.
@export var pool_damage_fraction: float = 0.45


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var enemy := actor as Enemy
	if enemy == null or enemy.data == null or flask_scene == null:
		return FAILURE

	var flask := ObjectPool.acquire(flask_scene) as EnemyFlask
	if flask == null:
		push_error("ActionThrowFlask: flask_scene no es un EnemyFlask")
		return FAILURE

	var origin: Vector3 = enemy.global_position + Vector3.UP * enemy.data.head_offset
	# A los pies y no al pecho: el charco se apoya en el piso, así que el arco
	# tiene que terminar en el piso o el frasco explota a la altura de la cintura
	# y el charco aparece flotando por encima del suelo que dice negar.
	var target: Vector3 = enemy.get_player_position()

	flask.setup_pool(pool_radius, pool_duration,
		enemy.data.damage * pool_damage_fraction)
	flask.launch_with_velocity(origin, _arc_to(origin, target), enemy)
	AudioPool.play_3d(enemy.data.attack_sound, origin, AudioPool.BUS_ENEMIES)
	enemy.start_attack_cooldown()
	return SUCCESS


## El mismo solver balístico que usan `JumpLink.get_launch_velocity()` y
## `Enemy.start_leap()`: horizontal a velocidad constante, vertical compensando la
## caída del vuelo entero. Resuelto una vez al soltar y nunca corregido - por eso
## moverse funciona.
##
## La gravedad sale de `ThrownUtility`, que es quien después va a integrar el
## vuelo. Escribir un 18.0 acá lo desincronizaría en silencio el día que alguien
## toque la de allá, y el síntoma sería que los frascos caen cortos.
func _arc_to(from: Vector3, to: Vector3) -> Vector3:
	var time: float = maxf(flight_time, 0.1)
	var offset: Vector3 = to - from
	var velocity := Vector3(offset.x, 0.0, offset.z) / time
	velocity.y = offset.y / time + 0.5 * ThrownUtility.get_gravity() * time
	return velocity
