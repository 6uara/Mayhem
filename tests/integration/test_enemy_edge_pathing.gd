extends GutTest
## El síntoma reportado: enemigos trabados contra los bordes del arena.
##
## La sospecha, y lo que se prueba acá: el punto al que un enemigo quiere caminar
## no está obligado a existir. `get_approach_position()` empuja el destino hacia
## afuera del jugador -por el flanco, por la espalda, por el carril lateral- y con
## el jugador cerca de la pared eso cae **fuera del navmesh**, en la franja muerta
## entre la pared invisible y el borde del piso, o directamente en el vacío.
##
## Un destino ahí no falla: el agente rutea hasta lo más cerca que puede, que es
## la pared, y el enemigo se queda empujando contra ella. Desde afuera se ve
## exactamente como "se trabó en el borde", y no hay ningún error que lo diga.
##
## Los tres arquetipos con rumbo son los expuestos, y el Bomber es el peor caso
## porque su rumbo es 180°: cuando el jugador pelea de espaldas a la pared, el
## punto que el Bomber quiere ocupar está *dentro* de la pared, siempre.

const ARENA: String = "res://scenes/arena/greybox_arena.tscn"
const ENEMY_SCENE: String = "res://scenes/enemies/enemy.tscn"

var _arena: Node3D = null
var _player: Node3D = null


func before_each() -> void:
	_arena = load(ARENA).instantiate()
	add_child_autofree(_arena)
	await wait_physics_frames(4)
	NavigationServer3D.map_force_update(_map())
	_player = Node3D.new()
	_player.add_to_group(&"player")
	add_child_autofree(_player)


func _map() -> RID:
	return (_arena.get_node("Navigation") as NavigationRegion3D).get_navigation_map()


## Cuánto se aleja un punto del navmesh. 0 = está parado en él.
func _off_mesh_by(point: Vector3) -> float:
	var closest: Vector3 = NavigationServer3D.map_get_closest_point(_map(), point)
	return Vector2(point.x - closest.x, point.z - closest.z).length()


## El borde jugable, medido y no escrito a mano: el punto del navmesh más lejano
## del centro en una dirección, que es donde el jugador puede efectivamente estar.
func _edge_in(direction: Vector3) -> Vector3:
	var far: Vector3 = direction.normalized() * 200.0
	return NavigationServer3D.map_get_closest_point(_map(), far)


func _spawn(archetype: String, at: Vector3) -> Enemy:
	var enemy: Enemy = load(ENEMY_SCENE).instantiate()
	add_child_autofree(enemy)
	await wait_physics_frames(1)
	enemy.setup(load("res://data/enemies/%s.tres" % archetype), at)
	await wait_physics_frames(1)
	return enemy


## Con el jugador contra la pared, el punto de aproximación de un Bomber cae del
## otro lado. Es la reproducción del reporte.
func test_a_bomber_never_asks_to_walk_outside_the_arena() -> void:
	var edge: Vector3 = _edge_in(Vector3.RIGHT)
	_player.global_position = edge
	# Mirando hacia adentro, o sea con la pared a la espalda: el caso normal de
	# pelear acorralado, y el peor caso del rumbo de 180 grados.
	_player.look_at(Vector3(0.0, edge.y, 0.0), Vector3.UP)
	await wait_physics_frames(1)

	var bomber: Enemy = await _spawn("bomber", edge - Vector3.RIGHT * 14.0)
	# Lo que hace la hoja de perseguir, tal cual: pide el punto de flanqueo y
	# camina hacia el. El punto crudo puede caer afuera -es geometria alrededor del
	# jugador, no una consulta al navmesh-, y lo que no puede es que el destino
	# quede afuera.
	bomber.set_move_target(bomber.get_approach_position())
	assert_lt(_off_mesh_by(bomber.move_target), 1.0,
		"el Bomber camina a %.1f m fuera del navmesh" % _off_mesh_by(bomber.move_target))


## Lo mismo por el flanco, que es más común: un Environmental se para a 12m del
## jugador de costado, y contra una pared esos 12m caen afuera.
func test_an_environmental_never_asks_to_stand_outside_the_arena() -> void:
	var edge: Vector3 = _edge_in(Vector3.BACK)
	_player.global_position = edge
	_player.look_at(Vector3(0.0, edge.y, 0.0), Vector3.UP)
	await wait_physics_frames(1)

	var env: Enemy = await _spawn("environmental", edge - Vector3.BACK * 20.0)
	env.set_move_target(env.get_approach_position())
	assert_lt(_off_mesh_by(env.move_target), 1.0,
		"el Environmental se para a %.1f m fuera del navmesh" % _off_mesh_by(env.move_target))


## Y el carril lateral, que lo tienen los cinco arquetipos de siempre: es el mismo
## empujón hacia afuera, más chico.
func test_the_side_lane_stays_inside_the_arena_too() -> void:
	var edge: Vector3 = _edge_in(Vector3.RIGHT)
	_player.global_position = edge
	await wait_physics_frames(1)

	var rusher: Enemy = await _spawn("rusher", edge - Vector3.RIGHT * 10.0)
	# El peor carril posible, en vez de esperar a que el azar lo elija.
	rusher._approach_lane = 1.0
	rusher.set_move_target(rusher.get_approach_position())
	assert_lt(_off_mesh_by(rusher.move_target), 1.0,
		"el carril lateral saca al Rusher %.1f m del navmesh" % _off_mesh_by(rusher.move_target))


## La red de la corrección: un destino que ya era válido no se toca. Si el clamp
## moviera puntos buenos, cambiaría el comportamiento de los cinco arquetipos
## originales en medio del arena, que es donde pasa el 90% del juego.
func test_a_reachable_destination_is_left_exactly_where_it_was() -> void:
	_player.global_position = Vector3.ZERO
	await wait_physics_frames(1)
	var rusher: Enemy = await _spawn("rusher", Vector3(8.0, 0.0, 0.0))
	var wanted := Vector3(3.0, 0.0, 2.0)

	rusher.set_move_target(wanted)
	assert_almost_eq(rusher.move_target.distance_to(wanted), 0.0, 0.05,
		"en medio del arena el destino queda donde estaba")


## Y el destino corregido sigue sirviendo para lo que existe: queda del lado del
## jugador, no en cualquier punto del navmesh que resulte cercano. Un clamp que
## mande al Bomber al otro extremo del arena arregla el atasco y rompe el
## arquetipo.
func test_the_correction_pulls_the_destination_toward_the_player() -> void:
	var edge: Vector3 = _edge_in(Vector3.RIGHT)
	_player.global_position = edge
	_player.look_at(Vector3(0.0, edge.y, 0.0), Vector3.UP)
	await wait_physics_frames(1)

	var bomber: Enemy = await _spawn("bomber", edge - Vector3.RIGHT * 14.0)
	var raw: Vector3 = bomber.get_approach_position()
	bomber.set_move_target(raw)
	assert_lt(bomber.move_target.distance_to(_player.global_position),
		raw.distance_to(_player.global_position) + 0.01,
		"el destino se acerca al jugador, no se aleja")
	assert_lt(bomber.move_target.distance_to(_player.global_position), 6.0,
		"y sigue siendo un punto alrededor del jugador")


# ------------------------------------------------- aparecer del lado equivocado

## El segundo síntoma reportado: los que salen por puertas lejanas recorren el
## borde del arena y recién después se destraban.
##
## No era el steering. El piso se bakea entero, incluida la franja de afuera de la
## pared invisible, y esa franja es una isla navegable **sin comunicación con el
## interior**; encima el interior se erosiona 0.85m hacia adentro (el
## `agent_radius` del bake). Entre las dos cosas queda una banda de un par de
## metros donde una puerta está físicamente adentro del arena y su polígono más
## cercano es el anillo de afuera. Cinco de las siete puertas caen ahí.
func test_every_door_puts_its_enemies_somewhere_they_can_walk_from() -> void:
	_player.global_position = Vector3.ZERO
	await wait_physics_frames(1)
	var doors: Array = get_tree().get_nodes_in_group(&"spawn_door")
	assert_gt(doors.size(), 0, "hay puertas")

	for node: Node in doors:
		var door := node as SpawnDoor
		var rusher: Enemy = await _spawn("rusher", door.get_spawn_position())
		assert_true(_can_walk_to_centre(rusher.global_position),
			"%s deja al enemigo en una isla desde la que no se llega al centro"
				% door.door_id)


## Y la corrección es un empujón, no un teletransporte: el enemigo tiene que
## seguir apareciendo en su puerta.
func test_the_spawn_correction_is_small() -> void:
	_player.global_position = Vector3.ZERO
	await wait_physics_frames(1)
	for node: Node in get_tree().get_nodes_in_group(&"spawn_door"):
		var door := node as SpawnDoor
		var wanted: Vector3 = door.get_spawn_position()
		var rusher: Enemy = await _spawn("rusher", wanted)
		var moved: float = Vector2(rusher.global_position.x - wanted.x,
			rusher.global_position.z - wanted.z).length()
		# Medido: las cinco puertas que caían del lado malo se arreglan con un
		# metro. Tres es red, no expectativa.
		assert_lt(moved, 3.0,
			"%s corrige %.1f m: eso ya no es aparecer en la puerta" % [door.door_id, moved])


func _can_walk_to_centre(from: Vector3) -> bool:
	var path: PackedVector3Array = NavigationServer3D.map_get_path(_map(), from,
		Vector3.ZERO, true)
	if path.is_empty():
		return false
	return path[path.size() - 1].distance_to(Vector3.ZERO) <= 2.0
