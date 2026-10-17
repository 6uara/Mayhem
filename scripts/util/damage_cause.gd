class_name DamageCause
extends RefCounted
## De que vino un golpe, dicho como un id corto: el arquetipo que pego, la arena,
## o el propio jugador.
##
## Existe para el playtest. `HealthComponent` ya sabia quien pego -para pagar la
## kill- pero al jugador le llegaba el daño sin origen, y el log de una run decia
## cuanto daño entro y nunca de donde. "Murio en la ola 7" no dice si la 7 esta
## mal balanceada o si los Rangers de la 6 lo dejaron en un tercio de vida.
##
## Utilidad estatica, como Players y Factions: lo que importa es que todas las
## fuentes de daño nombren igual las mismas cosas.

## Un charco o una trampa del arena, que no son de nadie.
const ARENA: StringName = &"arena"
## El propio jugador: su explosion, su rebote. Hoy casi nunca pasa; con armas de
## area si.
const SELF: StringName = &"self"

const ENEMY_DATA_PATH: String = "res://data/enemies/%s.tres"


## El id de quien causo el golpe. Sube por los padres como
## `Enemy._killed_by_the_player()`: una utilidad o un charco puede atribuirse a un
## hijo de quien lo puso.
static func of(attacker: Node) -> StringName:
	var node: Node = attacker
	while node != null and is_instance_valid(node):
		var enemy := node as Enemy
		if enemy != null and enemy.data != null:
			return enemy.data.id
		if node.is_in_group(&"player"):
			return SELF
		node = node.get_parent()
	return ARENA


## Como se nombra en pantalla.
static func label(cause: StringName) -> String:
	match cause:
		ARENA:
			return "the arena"
		SELF:
			return "yourself"
		&"":
			return "unknown"
	var path: String = ENEMY_DATA_PATH % cause
	if ResourceLoader.exists(path):
		var data := load(path) as EnemyData
		if data != null and data.display_name != "":
			return data.display_name
	return String(cause).capitalize()
