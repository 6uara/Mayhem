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
## Cuanto se adelanta a donde el jugador va a estar, como fraccion del vuelo.
##
## 0 tira a donde esta parado, que es tirarle siempre a la espalda: para cuando
## el frasco llega, el jugador ya se movio, y el charco queda atras suyo negando
## terreno que acababa de dejar. Nunca lo obliga a nada.
##
## 1.0 seria puntería perfecta, y es igual de malo por el otro lado: se vuelve
## inesquivable corriendo derecho y la unica respuesta es frenar en seco. En el
## medio el charco cae *en el camino*, delante del jugador, y la pregunta pasa a
## ser "sigo por acá o me desvío" - que es la unica pregunta que este arquetipo
## sabe hacer.
@export_range(0.0, 1.0, 0.05) var lead_fraction: float = 0.65

@export_group("Frasco de atrapado")
## La segunda carga del arquetipo: un charco que no lastima, frena
## (PLAN_NEW_ENEMY_TYPES §4.2). Vacío = el Environmental sólo tira ácido, que es
## exactamente como se comportaba antes de que esto existiera.
@export var snare_flask_scene: PackedScene
## Uno de cada cuántos tiros es de atrapado. 0 = ninguno.
##
## Alternar y no elegir por situación es a propósito: el jugador tiene que poder
## anticipar cuál viene, y el aviso es el arco - el frasco vuela 1.1s y se ve de
## qué color es. Un charco que frena sin haberse podido leer antes de caer es la
## versión hostil de este arquetipo.
@export var snare_every: int = 2
## Más chico que el de ácido: se lo esquiva peor, porque frenarse dentro cuesta
## salir. Un charco de atrapado del tamaño del de ácido es una condena.
@export var snare_radius: float = 2.6
@export var snare_duration: float = 4.0

## Cuántos frascos van tirados. Vive en la hoja y no en `Enemy` porque es de este
## ataque: cada Environmental lleva su propia cuenta, igual que su cadencia.
var _throws: int = 0


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var enemy := actor as Enemy
	if enemy == null or enemy.data == null or flask_scene == null:
		return FAILURE

	var is_snare: bool = _next_is_snare()
	var scene: PackedScene = snare_flask_scene if is_snare else flask_scene
	var flask := ObjectPool.acquire(scene) as EnemyFlask
	if flask == null:
		push_error("ActionThrowFlask: la escena del frasco no es un EnemyFlask")
		return FAILURE
	_throws += 1

	var origin: Vector3 = enemy.global_position + Vector3.UP * enemy.data.head_offset
	# A los pies y no al pecho: el charco se apoya en el piso, así que el arco
	# tiene que terminar en el piso o el frasco explota a la altura de la cintura
	# y el charco aparece flotando por encima del suelo que dice negar.
	var target: Vector3 = _predicted_spot(enemy)

	if is_snare:
		# Sin daño: frenar y quemar a la vez son dos castigos por una decisión, y
		# el que este charco cobra es el de posición. Ver `SnareZone`.
		flask.setup_pool(snare_radius, snare_duration, 0.0)
	else:
		flask.setup_pool(pool_radius, pool_duration,
			enemy.data.damage * pool_damage_fraction)
	flask.launch_with_velocity(origin, _arc_to(origin, target), enemy)
	AudioPool.play_3d(enemy.data.attack_sound, origin, AudioPool.BUS_ENEMIES)
	enemy.start_attack_cooldown()
	return SUCCESS


## A dónde va a estar el jugador cuando el frasco llegue, no dónde está ahora.
##
## Es lo que convierte al arquetipo de "te tira cosas" en "te corta el camino".
## Sólo se adelanta con la parte horizontal de la velocidad: sumar la vertical
## haría que un jugador saltando reciba el charco por encima o por debajo del
## piso, y el charco vive en el suelo.
##
## No corrige por el terreno. Si el punto predicho cae en el vacío, el frasco
## sigue volando hasta que algo lo pare o hasta la red de seguridad de
## `ThrownUtility` - errar es el modo normal de funcionar de este arquetipo, así
## que no hace falta protegerlo de eso.
func _predicted_spot(enemy: Enemy) -> Vector3:
	var here: Vector3 = enemy.get_target_position()
	if lead_fraction <= 0.0:
		return here
	var velocity: Vector3 = enemy.get_target_velocity()
	velocity.y = 0.0
	return here + velocity * maxf(flight_time, 0.1) * lead_fraction


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


## Si el próximo tiro es de atrapado. El primero nunca lo es: el arquetipo se
## presenta con lo que ya sabe hacer y recién después cambia la carga.
func _next_is_snare() -> bool:
	if snare_flask_scene == null or snare_every <= 0:
		return false
	return (_throws + 1) % snare_every == 0
