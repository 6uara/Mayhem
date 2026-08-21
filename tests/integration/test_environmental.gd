extends GutTest
## El Environmental: no te pega, te saca de donde estás parado.
##
## Tira frascos en parábola al piso bajo el jugador, y donde caen queda un charco.
## Lo que se prueba acá es que el frasco llegue donde apunta y que lo que deja sea
## un `HazardZone` de verdad - o sea, que herede la telegrafía en vez de esquivarla.
##
## El frasco de atrapado (el que inmoviliza) NO existe todavía: es el paso 8 del
## plan, último a propósito porque es el que más pelea con el pilar de movilidad.

const FLASK_SCENE: String = "res://scenes/enemies/enemy_flask.tscn"
const ENVIRONMENTAL: String = "res://data/enemies/environmental.tres"


func after_each() -> void:
	ObjectPool.release_all()
	await wait_physics_frames(2)


func _flask() -> EnemyFlask:
	var flask := ObjectPool.acquire(load(FLASK_SCENE)) as EnemyFlask
	assert_not_null(flask, "la escena del frasco es un EnemyFlask")
	return flask


## Un piso para que el frasco tenga dónde aterrizar. Sin esto vuela para siempre
## y el test mide la red de seguridad en vez del arco.
func _make_floor() -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(shape)
	body.collision_layer = PhysicsLayers.WORLD
	add_child_autofree(body)
	return body


# --------------------------------------------------------------------- el arco

## Lo único que el solver balístico promete: que el frasco caiga donde apuntó.
## Si la gravedad del solver y la del vuelo se separan, cae corto y nada lo dice.
func test_the_flask_lands_where_it_was_aimed() -> void:
	_make_floor()
	var flask: EnemyFlask = _flask()
	var origin := Vector3(0.0, 2.0, 0.0)
	var target := Vector3(12.0, 0.0, 5.0)
	var flight: float = 1.1

	var offset: Vector3 = target - origin
	var velocity := Vector3(offset.x, 0.0, offset.z) / flight
	velocity.y = offset.y / flight + 0.5 * ThrownUtility.get_gravity() * flight
	flask.launch_with_velocity(origin, velocity, null)

	await wait_seconds(flight + 0.35)
	# Ya volvió al pool, así que se mide el charco que dejó y no el frasco.
	var pools: Array[Node] = _live_hazards()
	assert_eq(pools.size(), 1, "dejó exactamente un charco")
	if pools.is_empty():
		return
	var landed: Vector3 = (pools[0] as Node3D).global_position
	assert_almost_eq(landed.x, target.x, 1.0, "cayó donde apuntó, en x")
	assert_almost_eq(landed.z, target.z, 1.0, "cayó donde apuntó, en z")


## La gravedad del arco tiene que salir de quien después integra el vuelo. Son dos
## lugares distintos y el síntoma de que se separaron es "los frascos caen cortos",
## que nadie lee como un bug de dos constantes.
func test_the_solver_and_the_flight_share_one_gravity() -> void:
	assert_gt(ThrownUtility.get_gravity(), 0.0,
		"ThrownUtility publica su gravedad para que el solver use la misma")


# -------------------------------------------------------------------- el charco

## El charco es un HazardZone sin modificar, y eso es el punto: hereda gratis el
## aviso de 0.6s y el decal al radio exacto del daño. Un área propia habría podido
## saltarse las dos cosas sin que nada fallara.
func test_what_it_leaves_behind_is_a_real_hazard_zone() -> void:
	_make_floor()
	var flask: EnemyFlask = _flask()
	flask.setup_pool(4.0, 5.0, 9.0)
	flask.launch_with_velocity(Vector3(0.0, 3.0, 0.0), Vector3(0.0, -1.0, 0.0), null)
	# Tiene que caer 3m con gravedad 18: son ~0.5s, no seis frames de fisica.
	await wait_seconds(0.7)

	var pools: Array[Node] = _live_hazards()
	assert_eq(pools.size(), 1, "un charco")
	if pools.is_empty():
		return
	var zone := pools[0] as HazardZone
	assert_not_null(zone, "lo que deja es un HazardZone")
	assert_almost_eq(zone.radius, 4.0, 0.01, "el radio es el que se le pidió")
	assert_almost_eq(zone.damage, 9.0, 0.01, "y el daño también")


## El decal es la promesa. Se prueba acá además de en el hazard porque el frasco
## es quien elige el radio, y elegir uno que el dibujo no acompañe es la forma en
## que esta ley se rompe desde afuera.
func test_the_pool_warns_before_it_can_hurt_anyone() -> void:
	_make_floor()
	var flask: EnemyFlask = _flask()
	flask.setup_pool(3.0, 6.0, 8.0)
	flask.launch_with_velocity(Vector3(0.0, 3.0, 0.0), Vector3(0.0, -1.0, 0.0), null)
	# Tiene que caer 3m con gravedad 18: son ~0.5s, no seis frames de fisica.
	await wait_seconds(0.7)

	var pools: Array[Node] = _live_hazards()
	if pools.is_empty():
		assert_true(false, "no dejó charco")
		return
	var zone := pools[0] as HazardZone
	assert_false(zone.is_armed, "recién caído todavía no lastima: está avisando")

	await wait_seconds(Tokens.HAZARD_WARNING + 0.2)
	assert_true(zone.is_armed, "pasado el aviso, ahora sí")


# --------------------------------------------------------------- sobre la horda

## El frasco pasa por encima de sus propios compañeros. Las utilidades del jugador
## hacen lo contrario a propósito - una granada que atraviesa a quien apuntaste es
## una carga desperdiciada - y por eso la máscara es del payload y no de la clase
## base: acá, frenarse contra el primer aliado convierte la negación de terreno en
## un charco a los pies del que lo tiró.
func test_the_flask_flies_over_the_horde_instead_of_hitting_it() -> void:
	var flask: EnemyFlask = _flask()
	await wait_physics_frames(1)
	assert_eq(flask.hit_mask & PhysicsLayers.ENEMY, 0,
		"el frasco no choca con la horda")
	assert_gt(flask.hit_mask & PhysicsLayers.WORLD, 0,
		"pero sí con el mundo, o no aterriza nunca")


func _live_hazards() -> Array[Node]:
	var found: Array[Node] = []
	for node: Node in get_tree().get_nodes_in_group(&"hazard"):
		# Los pooleados que ya volvieron al pool siguen en el arbol, apagados.
		if node.is_in_group(ObjectPool.RELEASED_GROUP):
			continue
		found.append(node)
	return found
