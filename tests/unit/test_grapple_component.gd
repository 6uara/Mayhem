extends GutTest
## GrappleComponent had zero test coverage before this - these guard the exact
## playtest report that finally forced it: aiming at an anchor and firing felt
## like a small hop instead of a swing.

var _body: CharacterBody3D
var _grapple: GrappleComponent


func before_each() -> void:
	_body = CharacterBody3D.new()
	add_child_autofree(_body)
	_grapple = GrappleComponent.new()
	_grapple.body = _body
	add_child_autofree(_grapple)
	await wait_frames(1)


## should_release() used to run the "moving away from the anchor" check on the same
## physics frame try_fire() succeeded - before the pull had touched velocity even
## once. Firing while carrying velocity with any component away from the anchor
## (backpedaling, strafing, residual momentum from a slide) made it true instantly,
## and all that played out was the release's small upward kick: a hop, not a swing.
func test_a_fresh_grapple_survives_moving_away_within_the_grace_window() -> void:
	_body.global_position = Vector3.ZERO
	_grapple._anchor = Vector3(10, 0, 0)
	_grapple.is_grappling = true
	_grapple._fired_at_msec = Time.get_ticks_msec()
	# Moving directly away from the anchor - the exact shape of the old bug.
	_body.velocity = Vector3(-5, 0, 0)

	assert_false(_grapple.should_release(),
		"a grapple must not end before the pull has had a chance to act")


## Distance is a real arrival, not a false positive - that check must never wait.
func test_arriving_at_the_anchor_releases_immediately_even_within_the_grace_window() -> void:
	_grapple._anchor = Vector3(1.0, 0, 0)
	_body.global_position = Vector3.ZERO
	_grapple.is_grappling = true
	_grapple._fired_at_msec = Time.get_ticks_msec()
	_body.velocity = Vector3.ZERO

	assert_true(_grapple.should_release(),
		"being inside arrive_distance must release regardless of timing")


## The grace window is a delay, not a waiver - a swing that is still departing once
## the pull has had its say must end.
func test_departure_still_releases_once_the_grace_window_has_passed() -> void:
	_body.global_position = Vector3.ZERO
	_grapple._anchor = Vector3(10, 0, 0)
	_grapple.is_grappling = true
	_grapple._fired_at_msec = Time.get_ticks_msec() - int(_grapple.min_flight_time * 1000.0) - 50
	_body.velocity = Vector3(-5, 0, 0)

	assert_true(_grapple.should_release(),
		"a grapple that is still moving away after the grace window must end")


func test_should_release_is_true_when_not_grappling() -> void:
	_grapple.is_grappling = false
	assert_true(_grapple.should_release())



# ------------------------------------------------- encadenar en el aire

## `is_on_floor()` de verdad solo dice true despues de un move_and_slide contra
## una superficie, y un test unitario no tiene ninguna. Pisar el metodo nativo en
## un CharacterBody3D falso tampoco sirve: Godot lo rechaza, y una llamada tipada
## iria igual al metodo nativo. Por eso el componente pregunta por el piso a
## traves de su propio `_is_airborne()`, que es el punto que esto reemplaza.
class GroundedGrapple:
	extends GrappleComponent

	var airborne: bool = true

	func _is_airborne() -> bool:
		return airborne


func _chainable_grapple() -> GroundedGrapple:
	var grapple := GroundedGrapple.new()
	grapple.body = _body
	grapple.cooldown = 5.0
	grapple.ground_grace = 2.0
	add_child_autofree(grapple)
	return grapple


## El pedido del playtest: soltarse en el aire y volver a engancharse enseguida.
func test_releasing_in_the_air_leaves_the_grapple_ready_to_chain() -> void:
	var grapple: GroundedGrapple = _chainable_grapple()
	await wait_frames(1)

	grapple.airborne = true
	grapple.is_grappling = true
	grapple.release()

	assert_false(grapple.is_grappling, "solto")
	assert_eq(grapple._cooldown_left, 0.0, "encadenar en el aire no cobra cooldown")


## La otra mitad de la regla: el cooldown no desaparece, se difiere.
func test_two_seconds_on_the_ground_finally_charge_the_cooldown() -> void:
	var grapple: GroundedGrapple = _chainable_grapple()
	await wait_frames(1)

	grapple.airborne = true
	grapple.is_grappling = true
	grapple.release()

	grapple.airborne = false
	grapple._tick_chain_debt(2.1)

	assert_gt(grapple._cooldown_left, 0.0, "quedarse en el piso cobra lo que se debia")


## Tocar y salir no paga nada - es lo que mantiene vivo un recorrido que pasa
## rozando una plataforma.
func test_touching_down_briefly_does_not_charge_the_cooldown() -> void:
	var grapple: GroundedGrapple = _chainable_grapple()
	await wait_frames(1)

	grapple.airborne = true
	grapple.is_grappling = true
	grapple.release()

	grapple.airborne = false
	grapple._tick_chain_debt(1.0)
	grapple.airborne = true
	grapple._tick_chain_debt(0.1)
	grapple.airborne = false
	grapple._tick_chain_debt(1.5)

	assert_eq(grapple._cooldown_left, 0.0,
		"el contador de piso se reinicia al despegar, no se acumula")


## Soltarse ya parado en el piso es el caso viejo y no cambia.
func test_releasing_on_the_ground_charges_the_cooldown_immediately() -> void:
	var grapple: GroundedGrapple = _chainable_grapple()
	await wait_frames(1)

	grapple.airborne = false
	grapple.is_grappling = true
	grapple.release()

	assert_gt(grapple._cooldown_left, 0.0, "sin vuelo no hay encadenado que premiar")


# ------------------------------------------------- asistencia de apuntado

## Anclas de verdad, en el arbol y en la capa GRAPPLE_ANCHOR: la busqueda del
## cono recorre el grupo y despues consulta el servidor de fisica por linea de
## vista, asi que un doble no alcanza para probarla.
## El collider va chico a proposito: lo que se prueba es el cono, y un ancla
## gorda la engancha el raycast directo antes de que el cono llegue a opinar.
func _make_anchor(at: Vector3) -> StaticBody3D:
	var anchor := StaticBody3D.new()
	anchor.collision_layer = PhysicsLayers.GRAPPLE_ANCHOR
	anchor.collision_mask = 0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.1
	shape.shape = sphere
	anchor.add_child(shape)
	add_child_autofree(anchor)
	anchor.global_position = at
	anchor.add_to_group(GrappleAnchor.GROUP)
	return anchor


## Una pared solida entre el jugador y lo que quiera enganchar.
func _make_wall(at: Vector3, size: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = PhysicsLayers.WORLD
	wall.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)
	add_child_autofree(wall)
	wall.global_position = at
	return wall


## `aim_node` mirando a -Z desde el origen, que es la orientacion que da un
## `Node3D` recien creado sin rotar.
func _aiming_grapple() -> GrappleComponent:
	var aim := Node3D.new()
	add_child_autofree(aim)
	aim.global_position = Vector3.ZERO
	_grapple.aim_node = aim
	_body.global_position = Vector3.ZERO
	return _grapple


## El pedido: la reticula apenas afuera del ancla igual engancha.
func test_an_anchor_just_off_the_reticle_is_still_grabbed() -> void:
	var grapple: GrappleComponent = _aiming_grapple()
	# ~2.9 grados de desvio a 20m, dentro de los 4 de base y fuera del collider.
	_make_anchor(Vector3(1.0, 0.0, -20.0))
	await wait_physics_frames(2)

	assert_false(grapple._find_anchor().is_empty(),
		"un desvio de tres grados tiene que perdonarse")


## Y la otra mitad: la asistencia corrige el pixel, no apunta por el jugador.
func test_an_anchor_well_outside_the_cone_is_not_grabbed() -> void:
	var grapple: GrappleComponent = _aiming_grapple()
	# ~26 grados: mirando claramente para otro lado.
	_make_anchor(Vector3(10.0, 0.0, -20.0))
	await wait_physics_frames(2)

	assert_true(grapple._find_anchor().is_empty(),
		"la asistencia no puede apuntar por el jugador")


## La garantia que daba el raycast unico y no se puede perder.
func test_the_cone_does_not_reach_through_a_wall() -> void:
	var grapple: GrappleComponent = _aiming_grapple()
	_make_anchor(Vector3(1.0, 0.0, -20.0))
	_make_wall(Vector3(0.0, 0.0, -10.0), Vector3(20.0, 20.0, 1.0))
	await wait_physics_frames(2)

	assert_true(grapple._find_anchor().is_empty(),
		"no se engancha a traves de una pared, apunte como apunte")


## Con dos en el cono gana la mejor apuntada, no la mas cercana: la pregunta que
## la asistencia contesta es "a cual estabas apuntando".
func test_the_best_aimed_anchor_wins_over_the_closest_one() -> void:
	var grapple: GrappleComponent = _aiming_grapple()
	# 0.57 grados a veinte metros contra 3.3 a seis: las dos entran en el cono.
	var aligned: StaticBody3D = _make_anchor(Vector3(0.2, 0.0, -20.0))
	_make_anchor(Vector3(0.35, 0.0, -6.0))
	await wait_physics_frames(2)

	var hit: Dictionary = grapple._find_anchor()
	assert_eq(hit.get("collider"), aligned,
		"gana el menor angulo, no la distancia")


## Fuera de rango no hay cono que valga.
func test_the_cone_respects_max_range() -> void:
	var grapple: GrappleComponent = _aiming_grapple()
	grapple.max_range = 10.0
	_make_anchor(Vector3(0.2, 0.0, -20.0))
	await wait_physics_frames(2)

	assert_true(grapple._find_anchor().is_empty(),
		"el cono no puede estirar el alcance")


## Sin StatsComponent - los stubs de los tests, y cualquier wiring a medias - el
## componente tiene que caer en su propio export y no en cero.
func test_aim_assist_falls_back_to_the_export_without_stats() -> void:
	_grapple.stats = null
	_grapple.aim_assist_degrees = 7.0
	assert_almost_eq(_grapple.get_aim_assist_degrees(), 7.0, 0.001)


## Las mejoras se apilan, el cono no crece para siempre.
func test_aim_assist_is_capped() -> void:
	_grapple.stats = null
	_grapple.aim_assist_degrees = 999.0
	assert_almost_eq(_grapple.get_aim_assist_degrees(),
		GrappleComponent.MAX_AIM_ASSIST_DEGREES, 0.001)
