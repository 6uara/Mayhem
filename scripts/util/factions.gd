class_name Factions
extends Object
## Quién pelea contra quién. Utilidad estática, como PhysicsLayers y Players.
##
## Hasta acá el juego tenía dos bandos y ninguno estaba nombrado: eran el grupo
## `&"player"` y el grupo `&"enemy"`, y todo el código preguntaba por el primero.
## Eso alcanza mientras "hostil" y "el jugador" sean sinónimos. Dejan de serlo con
## los Gladiadores, que son una tercera facción que pelea contra las otras dos
## (PLAN_NEW_ENEMY_TYPES §5.2).
##
## La regla es una sola y no hay tabla que memorizar: **todos son hostiles a todos
## los que no son de su facción**. La única celda rara de la matriz del plan
## -horda contra horda, permitido sólo para la explosión del Bomber- no vive acá:
## vive en `Explosion`, que es el único que lastima sin preguntar. Poner la
## excepción en la matriz habría hecho que cualquier daño futuro entre miembros de
## la horda pareciera autorizado.

enum Id {
	PLAYER,
	## La horda de siempre: los siete arquetipos que entran por las puertas.
	HORDE,
	## Habitantes del arena, ni del jugador ni de la horda. Todavía no existen.
	GLADIATOR,
}


## De qué bando es este nodo. El grupo `&"player"` sigue siendo la verdad para el
## jugador -es lo que ya usaban treinta llamadas y no había motivo para moverlo-,
## y cualquier otra cosa la dice contestando `get_faction()`.
##
## Deliberadamente sin nombrar a `Enemy`. `enemy.gd` nombra a `EnemyData`, que
## nombra a `Factions` por el tipo del export: preguntarle acá el tipo a `Enemy`
## cerraría el ciclo, y GDScript a veces lo resuelve y a veces no según el orden
## en que compile - cuando no, la clase entera deja de existir y el error sale en
## sesenta tests que no tienen nada que ver. Ver la nota de `Explosion._victims()`,
## que es el precedente exacto.
static func of(node: Node) -> Id:
	if node == null or not is_instance_valid(node):
		return Id.HORDE
	if node.is_in_group(&"player"):
		return Id.PLAYER
	if node.has_method(&"get_faction"):
		return node.call(&"get_faction")
	return Id.HORDE


static func are_hostile(a: Id, b: Id) -> bool:
	return a != b


## Atajo para los dos nodos, que es como pregunta casi todo el código.
static func hostile(a: Node, b: Node) -> bool:
	if a == null or b == null or a == b:
		return false
	return are_hostile(of(a), of(b))


## En qué capa física vive el cuerpo de esta facción.
##
## Los Gladiadores tienen bit propio en vez de compartir `ENEMY` porque hay
## consultas que se resuelven en el servidor de física y no pueden preguntar por
## facción después: un proyectil de la horda tiene que **atravesar** a un
## compañero y **frenar** contra un Gladiador, y eso es una máscara, no un `if`.
static func body_layer(faction: Id) -> int:
	match faction:
		Id.PLAYER:
			return PhysicsLayers.PLAYER
		Id.GLADIATOR:
			return PhysicsLayers.GLADIATOR
		_:
			return PhysicsLayers.ENEMY


## Las capas de todo lo que esta facción puede lastimar. Para la horda hoy es
## `PLAYER | GLADIATOR`, y como no hay ningún cuerpo en `GLADIATOR` todavía, es
## exactamente la máscara que tenía antes de que existiera esto.
static func hostile_mask(faction: Id) -> int:
	var mask: int = 0
	for other: Id in [Id.PLAYER, Id.HORDE, Id.GLADIATOR]:
		if are_hostile(faction, other):
			mask |= body_layer(other)
	return mask
