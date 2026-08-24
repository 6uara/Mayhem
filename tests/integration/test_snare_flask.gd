extends GutTest
## El frasco de atrapado: el paso 8 del plan, y el único efecto del juego que le
## baja la velocidad al jugador.
##
## Lo que se prueba acá no es que frene -eso es un número- sino las tres cosas que
## lo hacen justo: que herede la telegrafía del `HazardZone` en vez de esquivarla,
## que **no** inmovilice y tenga salida (dash o gancho), y que soltar al que se
## fue sea automático, porque un charco que expira dejando al jugador lento para
## siempre es el peor bug posible de este arquetipo.

const SNARE_ZONE: String = "res://scenes/arena/snare_zone.tscn"
const SNARE_FLASK: String = "res://scenes/enemies/enemy_snare_flask.tscn"
const ENV_TREE: String = "res://scenes/enemies/ai/tree_environmental.tscn"


func after_each() -> void:
	ObjectPool.release_all()
	await wait_physics_frames(2)


# ------------------------------------------------------------------ el charco

## Es un HazardZone, y por eso avisa 0.6s antes de poder agarrar a nadie y dibuja
## el decal al radio exacto. Un área propia se habría podido saltear las dos.
func test_the_snare_pool_is_a_hazard_zone_and_inherits_the_telegraph() -> void:
	var zone := ObjectPool.acquire(load(SNARE_ZONE)) as SnareZone
	assert_not_null(zone, "la escena es un SnareZone")
	if zone == null:
		return
	assert_true(zone is HazardZone, "y un HazardZone, con toda su ley encima")
	zone.setup(0.0, 2.6, 4.0, null)
	assert_false(zone.is_armed, "recién puesto todavía no agarra: está avisando")
	assert_almost_eq(zone.radius, 2.6, 0.01, "el radio es el que se le pidió")

	await wait_seconds(Tokens.HAZARD_WARNING + 0.2)
	assert_true(zone.is_armed, "pasado el aviso, ahora sí")


## No lastima. Frenar y quemar a la vez es cobrar dos veces por una decisión, y lo
## que este charco le cobra al jugador es la posición.
func test_the_snare_pool_does_no_damage() -> void:
	var zone := ObjectPool.acquire(load(SNARE_ZONE)) as SnareZone
	if zone == null:
		assert_true(false, "no se pudo instanciar el charco")
		return
	assert_almost_eq(zone.damage, 0.0, 0.001, "el charco de atrapado no hace daño")


## El frasco de atrapado es el mismo objeto que el de ácido con otra carga: eso es
## lo que hizo que este paso costara una escena y no una clase.
func test_the_snare_flask_is_the_same_flask_with_another_payload() -> void:
	var flask := ObjectPool.acquire(load(SNARE_FLASK)) as EnemyFlask
	assert_not_null(flask, "sigue siendo un EnemyFlask")
	if flask == null:
		return
	await wait_physics_frames(1)
	assert_eq(flask.hit_mask & PhysicsLayers.ENEMY, 0,
		"y también pasa por encima de la horda")
	var payload := flask.hazard_scene.instantiate() as SnareZone
	assert_not_null(payload, "lo que deja es un SnareZone")
	if payload != null:
		payload.free()


# -------------------------------------------------------------- el jugador

func _movement() -> MovementComponent:
	var movement := MovementComponent.new()
	add_child_autofree(movement)
	return movement


## Fuerte, pero nunca cero: el juego se apoya entero en movilidad, y un charco que
## congela pelea contra su propio pilar.
func test_being_snared_slows_but_never_stops() -> void:
	var movement: MovementComponent = _movement()
	var free_speed: float = movement.get_move_speed()
	movement.apply_snare(0.35)
	assert_true(movement.is_snared(), "está atrapado")
	assert_lt(movement.get_move_speed(), free_speed, "se mueve más lento")
	assert_gt(movement.get_move_speed(), 0.0, "pero se mueve: nunca queda clavado")


## La salida. Sin esto el charco es un castigo; con esto es una pregunta - "¿gasto
## una carga de dash?" - que el jugador ya sabe contestar.
func test_breaking_the_snare_restores_full_speed() -> void:
	var movement: MovementComponent = _movement()
	var free_speed: float = movement.get_move_speed()
	movement.apply_snare(0.35)
	movement.break_snare()
	assert_false(movement.is_snared(), "salió")
	assert_almost_eq(movement.get_move_speed(), free_speed, 0.01,
		"y recupera toda su velocidad")


## Romperlo dashando no sirve de nada si el charco te vuelve a agarrar antes de
## que llegues al borde: la salida dura hasta que estés afuera.
func test_the_pool_cannot_re_snare_during_the_grace() -> void:
	var movement: MovementComponent = _movement()
	movement.apply_snare(0.35)
	movement.break_snare()
	movement.apply_snare(0.35)
	assert_false(movement.is_snared(),
		"el charco no vuelve a agarrar mientras dura la gracia")


## Y la gracia se acaba: volver a entrar al charco cuesta otra carga.
func test_the_grace_expires() -> void:
	var movement: MovementComponent = _movement()
	movement.break_snare()
	await wait_seconds(MovementComponent.SNARE_GRACE + 0.15)
	movement.apply_snare(0.35)
	assert_true(movement.is_snared(), "pasada la gracia, el charco agarra otra vez")


# ------------------------------------------------------------------ el arquetipo

## El Environmental alterna cargas. El primer tiro nunca es de atrapado: se
## presenta con lo que ya sabía hacer.
func test_the_environmental_alternates_payloads() -> void:
	var tree: Node = load(ENV_TREE).instantiate()
	add_child_autofree(tree)
	var throw := tree.get_node("Root/ThrowBranch/Throw") as ActionThrowFlask
	assert_not_null(throw, "el árbol tiene la hoja de tirar")
	if throw == null:
		return
	assert_not_null(throw.snare_flask_scene, "y una segunda carga cargada")
	assert_eq(throw.snare_every, 2, "uno de cada dos tiros atrapa")


# ------------------------------------------------- el atrapado se ve y se oye

## Estar atrapado tiene que anunciarse. Sin esto, el jugador no sabe por que esta
## lento y la salida que el charco tiene -dash o gancho- no se le ocurre nunca:
## el sistema entero se lee como que el juego se trabo.
func test_being_caught_announces_itself() -> void:
	var movement: MovementComponent = _movement()
	watch_signals(EventBus)
	movement.apply_snare(0.35)
	assert_signal_emitted(EventBus, "player_snared", "avisa que lo agarraron")


## Y avisa una sola vez, no diez por segundo: el charco re-aplica el efecto en
## cada refresco, y un aviso por refresco son diez sonidos por segundo.
func test_the_pool_refresh_does_not_re_announce() -> void:
	var movement: MovementComponent = _movement()
	movement.apply_snare(0.35)
	watch_signals(EventBus)
	movement.apply_snare(0.35)
	movement.apply_snare(0.35)
	assert_signal_emit_count(EventBus, "player_snared", 0, "solo avisa la transicion")


## Romperlo se anuncia distinto de que se te acabe el charco, y esa diferencia es
## la que ensena que romperlo fue una accion y no una casualidad.
func test_breaking_it_reads_differently_from_walking_out_of_it() -> void:
	var movement: MovementComponent = _movement()
	movement.apply_snare(0.35)
	watch_signals(EventBus)
	movement.break_snare()
	assert_signal_emitted_with_parameters(EventBus, "player_snare_ended", [true])

	movement.clear_snare()
	movement._snare_grace_left = 0.0
	movement.apply_snare(0.35)
	watch_signals(EventBus)
	movement.clear_snare()
	assert_signal_emitted_with_parameters(EventBus, "player_snare_ended", [false])


# ---------------------------------------------------------------- saturacion

func _throw_leaf() -> ActionThrowFlask:
	var tree: Node = load(ENV_TREE).instantiate()
	add_child_autofree(tree)
	return tree.get_node("Root/ThrowBranch/Throw") as ActionThrowFlask


## La negacion de terreno no escala lineal: dos charcos son el doble de trabajo y
## cuatro son un laberinto. El tope es lo que evita que tres Environmentals
## pavimenten el arena.
func test_the_arena_has_a_ceiling_of_live_pools() -> void:
	var throw: ActionThrowFlask = _throw_leaf()
	assert_gt(throw.max_live_pools, 0, "hay tope")
	assert_lte(throw.max_live_pools, 5, "y es un tope que se nota")


## El de atrapado se adelanta menos que el de acido, porque adelantarse con algo
## que te retiene no es lo mismo que adelantarse con algo que te empuja.
func test_the_snare_leads_less_than_the_acid() -> void:
	var throw: ActionThrowFlask = _throw_leaf()
	assert_lt(throw.snare_lead_fraction, throw.lead_fraction,
		"un charco que agarra no se tira tan adelante como uno que desvia")
	assert_gt(throw.snare_lead_fraction, 0.0,
		"pero sigue cortando el camino: tirarle a los pies es tirarle a la espalda")


## Un charco de atrapado encima de uno de acido es la unica configuracion del
## juego que puede matar sin que el jugador haya podido hacer nada.
func test_a_snare_is_never_thrown_on_top_of_a_live_pool() -> void:
	var throw: ActionThrowFlask = _throw_leaf()
	var zone := ObjectPool.acquire(load("res://scenes/arena/hazard_zone.tscn")) as HazardZone
	if zone == null:
		assert_true(false, "no se pudo instanciar el charco")
		return
	zone.global_position = Vector3.ZERO
	zone.radius = 3.2
	var live: Array[HazardZone] = [zone]

	assert_true(throw._overlaps_a_pool(Vector3(1.0, 0.0, 0.0), live),
		"encima del charco vivo: no")
	assert_false(throw._overlaps_a_pool(Vector3(12.0, 0.0, 0.0), live),
		"lejos del charco vivo: si")
