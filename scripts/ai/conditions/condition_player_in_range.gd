class_name ConditionPlayerInRange
extends ConditionLeaf
## Succeeds when the player is within `range_multiplier` x the archetype's attack range.
## Enemies always know where the player is (CLAUDE.md 5.3), so this is a geometry
## check, not a perception check.

## Multiplies EnemyData.attack_range. Use > 1 for "close enough to commit".
@export var range_multiplier: float = 1.0
## Set to use an absolute distance instead of the archetype's attack range.
@export var absolute_range: float = 0.0
## Mide contra EnemyData.leap_range en vez de attack_range.
##
## Un arquetipo que salta se compromete desde mucho mas lejos de lo que llega su
## golpe - el Rusher pega a 2.2m y salta desde 7m. Sin esto la rama del salto
## habria que abrirla con un multiplicador calculado a mano contra el alcance de
## golpe, que se desincroniza en silencio en cuanto alguien toca cualquiera de
## los dos numeros.
@export var use_leap_range: bool = false
## Mide contra el alcance al que el arquetipo arma su espoleta
## (EnemyData.fuse_arm_range, o attack_range si no declara uno).
##
## Mismo motivo que use_leap_range: una bomba se arma desde bastante mas lejos
## de lo que "golpea", y expresar esa distancia como un multiplicador a mano
## sobre attack_range se desincroniza en silencio en cuanto alguien mueve
## cualquiera de los dos numeros.
@export var use_fuse_range: bool = false
@export var invert: bool = false
## Ademas de la distancia, exige ver al objetivo.
##
## La distancia sola abria la rama de disparo contra una columna: el tirador se
## plantaba a su distancia preferida, telegrafiaba y disparaba a la pared el resto
## de la ola, porque `ActionKeepDistance` devolvia SUCCESS -esta a la distancia
## que queria- y el selector no llegaba nunca a la rama de acercarse. Desde
## afuera eso es un enemigo trabado, y encima uno que gasta el aviso sonoro del
## telegrafo sin que haya nada que esquivar.
##
## No es percepcion: el enemigo sigue sabiendo siempre donde esta el jugador
## (CLAUDE.md 5.3). Es la diferencia entre poder pegarle y no poder.
@export var require_line_of_sight: bool = false


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var enemy := actor as Enemy
	if enemy == null or enemy.data == null:
		return FAILURE
	var base_range: float = enemy.data.attack_range
	if use_leap_range:
		base_range = enemy.data.leap_range
	elif use_fuse_range:
		base_range = enemy.get_fuse_arm_range()
	var limit: float = absolute_range if absolute_range > 0.0 \
		else base_range * range_multiplier
	var in_range: bool = enemy.get_distance_to_target() <= limit
	if in_range and require_line_of_sight and not enemy.has_line_of_sight_to_target():
		in_range = false
	if invert:
		in_range = not in_range
	return SUCCESS if in_range else FAILURE
