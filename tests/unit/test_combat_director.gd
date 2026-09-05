extends GutTest
## El reparto de puestos, las fichas de ataque y el presupuesto de repath.
##
## Lo que se prueba aca es lo que ningun enemigo puede verificar solo: que dos del
## mismo rol no terminen en el mismo angulo, que el techo de ataques
## simultaneos se respete, y que ninguna de las dos cosas se filtre entre runs.


func after_each() -> void:
	CombatDirector.reset()


# Roles

func test_the_role_comes_from_how_the_archetype_fights() -> void:
	assert_eq(CombatDirector.role_of(load("res://data/enemies/rusher.tres")),
		CombatDirector.Role.BRAWLER, "el melee sin distancia preferida viene de frente")
	assert_eq(CombatDirector.role_of(load("res://data/enemies/ranger.tres")),
		CombatDirector.Role.SKIRMISHER, "el que pelea de lejos se para lejos")
	assert_eq(CombatDirector.role_of(load("res://data/enemies/bomber.tres")),
		CombatDirector.Role.INFILTRATOR, "la espoleta gana sobre todo lo demas")
	assert_eq(CombatDirector.role_of(load("res://data/enemies/environmental.tres")),
		CombatDirector.Role.ARTILLERY, "el que niega terreno tira predictivo")


func test_a_missing_archetype_still_gets_a_role() -> void:
	assert_eq(CombatDirector.role_of(null), CombatDirector.Role.BRAWLER)


# Puestos

## Lo que el reparto existe para evitar: dos del mismo rol pidiendo el mismo
## angulo, que en pantalla es un enemigo tapando al otro.
func test_no_two_slots_of_a_role_share_an_angle() -> void:
	for count: int in range(1, 9):
		var slots: Array[float] = CombatDirector.slots_for(
			CombatDirector.Role.SKIRMISHER, count)
		assert_eq(slots.size(), count, "%d puestos pedidos" % count)
		var seen: Array[float] = []
		for angle: float in slots:
			assert_false(seen.has(angle), "%d puestos: %f repetido" % [count, angle])
			seen.append(angle)


func test_slots_stay_inside_their_role_band() -> void:
	var band: Vector2 = CombatDirector.ROLE_BANDS[CombatDirector.Role.SKIRMISHER]
	for angle: float in CombatDirector.slots_for(CombatDirector.Role.SKIRMISHER, 6):
		var magnitude: float = absf(angle)
		assert_between(magnitude, band.x, band.y, "%f fuera de la banda" % angle)


## Los tiradores van a los costados del frente, nunca al centro: si pidieran 0
## grados serian Rushers que ademas disparan.
func test_skirmishers_never_take_the_centre() -> void:
	for angle: float in CombatDirector.slots_for(CombatDirector.Role.SKIRMISHER, 8):
		assert_gt(absf(angle), 40.0, "un tirador de frente no es un tirador")


## Y las bombas siempre por atras. La banda cruza los 180, asi que el envoltorio
## al otro lado del circulo tiene que dejarlas igual de atras.
func test_infiltrators_always_come_from_behind() -> void:
	for angle: float in CombatDirector.slots_for(CombatDirector.Role.INFILTRATOR, 6):
		assert_gt(absf(angle), 120.0, "%f no es el punto ciego" % angle)


## Alternar lado a lado y no llenar un costado primero: con tres tiradores, dos de
## un lado y uno del otro, nunca los tres juntos.
func test_slots_alternate_sides() -> void:
	var slots: Array[float] = CombatDirector.slots_for(CombatDirector.Role.SKIRMISHER, 3)
	var left: int = 0
	for angle: float in slots:
		if angle < 0.0:
			left += 1
	assert_between(left, 1, 2, "los tres puestos quedaron del mismo lado")


func test_no_slots_for_nobody() -> void:
	assert_eq(CombatDirector.slots_for(CombatDirector.Role.BRAWLER, 0).size(), 0)


# Fichas de ataque

func test_the_token_cap_holds() -> void:
	var cap: int = CombatDirector.ATTACK_TOKENS[CombatDirector.Role.BRAWLER]
	var granted: int = 0
	var holders: Array[Enemy] = []
	for i: int in cap + 3:
		var enemy: Enemy = _brawler()
		holders.append(enemy)
		if CombatDirector.request_attack_token(enemy):
			granted += 1
	assert_eq(granted, cap, "se repartieron mas fichas que el techo del rol")


func test_a_released_token_goes_back_to_the_pool() -> void:
	var cap: int = CombatDirector.ATTACK_TOKENS[CombatDirector.Role.BRAWLER]
	var holders: Array[Enemy] = []
	for i: int in cap:
		var enemy: Enemy = _brawler()
		holders.append(enemy)
		CombatDirector.request_attack_token(enemy)
	var extra: Enemy = _brawler()
	assert_false(CombatDirector.request_attack_token(extra), "el cupo esta lleno")
	CombatDirector.release_attack_token(holders[0])
	assert_true(CombatDirector.request_attack_token(extra), "y se libero uno")


## Pedirla dos veces no gasta dos: el arbol vuelve a tickear la misma hoja.
func test_asking_twice_costs_one_token() -> void:
	var enemy: Enemy = _brawler()
	assert_true(CombatDirector.request_attack_token(enemy))
	assert_true(CombatDirector.request_attack_token(enemy))
	CombatDirector.release_attack_token(enemy)
	assert_false(CombatDirector.holds_attack_token(enemy), "una sola ficha, una sola devolucion")


## La falla que no tira error: un enemigo que muere saltando se lleva el cupo
## puesto y el resto de la oleada nunca vuelve a saltar.
func test_dying_mid_leap_gives_the_token_back() -> void:
	var cap: int = CombatDirector.ATTACK_TOKENS[CombatDirector.Role.BRAWLER]
	var holders: Array[Enemy] = []
	for i: int in cap:
		var enemy: Enemy = _brawler()
		holders.append(enemy)
		CombatDirector.request_attack_token(enemy)
	CombatDirector.unregister(holders[0])
	assert_true(CombatDirector.request_attack_token(_brawler()),
		"la baja tiene que devolver la ficha")


func test_releasing_a_token_nobody_took_is_harmless() -> void:
	CombatDirector.release_attack_token(_brawler())
	CombatDirector.release_attack_token(null)
	assert_true(CombatDirector.request_attack_token(_brawler()), "el cupo quedo intacto")


# Presupuesto de repath

func test_the_repath_budget_runs_out_and_comes_back() -> void:
	var granted: int = 0
	for i: int in CombatDirector.REPATH_BUDGET_PER_FRAME + 5:
		if CombatDirector.request_repath():
			granted += 1
	assert_eq(granted, CombatDirector.REPATH_BUDGET_PER_FRAME, "cupo del frame")

	# Un enemigo registrado, o el director corta antes de reponer el cupo. Y uno
	# adentro del arbol: el director le pide la posicion global a todo el registro
	# para armar la grilla, y un nodo suelto no tiene ninguna.
	var enemy := Enemy.new()
	enemy.data = load("res://data/enemies/rusher.tres")
	enemy.is_active = true
	add_child_autofree(enemy)
	CombatDirector.register(enemy)
	await wait_physics_frames(2)
	assert_true(CombatDirector.request_repath(), "al frame siguiente hay turno de nuevo")


## El cupo se repartia por orden de llegada, y ese orden es el del arbol de
## escena: siempre el mismo. Con la horda pidiendo mas caminos de los que entran
## en un frame, los ultimos del arbol podian no conseguir turno nunca.
func test_whoever_was_denied_a_turn_gets_it_first_next_frame() -> void:
	var starved := Enemy.new()
	starved.data = load("res://data/enemies/rusher.tres")
	starved.is_active = true
	add_child_autofree(starved)
	CombatDirector.register(starved)

	# Los de mas arriba en el arbol se llevan el cupo entero, y el ultimo se queda
	# sin turno. Es el frame que antes se repetia igual toda la ola.
	for i: int in CombatDirector.REPATH_BUDGET_PER_FRAME:
		CombatDirector.request_repath()
	assert_false(CombatDirector.request_repath(starved), "este frame no le toco")

	await wait_physics_frames(1)
	# Los mismos de arriba vuelven a pedir primero, y ahora uno de sus turnos esta
	# reservado para el que quedo debiendo.
	var granted: int = 0
	for i: int in CombatDirector.REPATH_BUDGET_PER_FRAME:
		if CombatDirector.request_repath():
			granted += 1
	assert_eq(granted, CombatDirector.REPATH_BUDGET_PER_FRAME - 1,
		"al resto le queda el cupo menos lo reservado")
	assert_true(CombatDirector.request_repath(starved),
		"y el que se quedo sin turno lo cobra igual, aunque pida ultimo")


## La reserva no puede sobrevivir al que la genero: un enemigo que dejo de pedir
## caminos -murio, dejo de perseguir- estaria guardando cupo para siempre.
func test_a_debt_nobody_comes_to_collect_does_not_reserve_forever() -> void:
	var quitter := Enemy.new()
	quitter.data = load("res://data/enemies/rusher.tres")
	quitter.is_active = true
	add_child_autofree(quitter)
	CombatDirector.register(quitter)

	for i: int in CombatDirector.REPATH_BUDGET_PER_FRAME:
		CombatDirector.request_repath()
	assert_false(CombatDirector.request_repath(quitter), "queda debiendole un turno")

	# Pasada la ventana de prioridad sin que lo cobre, el cupo vuelve a ser de
	# todos. Ver REPATH_DEBT_FRAMES.
	await wait_physics_frames(CombatDirector.REPATH_DEBT_FRAMES + 2)
	var granted: int = 0
	for i: int in CombatDirector.REPATH_BUDGET_PER_FRAME:
		if CombatDirector.request_repath():
			granted += 1
	assert_eq(granted, CombatDirector.REPATH_BUDGET_PER_FRAME,
		"el cupo vuelve a estar entero")


# Reparto de piso

func test_two_throwers_cannot_claim_the_same_ground() -> void:
	assert_true(CombatDirector.claim_hazard(Vector3(10.0, 0.0, 10.0)))
	assert_false(CombatDirector.claim_hazard(Vector3(11.0, 0.0, 10.0)),
		"a un metro es el mismo charco")
	assert_true(CombatDirector.claim_hazard(
		Vector3(10.0 + CombatDirector.HAZARD_MIN_SEPARATION + 1.0, 0.0, 10.0)),
		"lo bastante lejos son dos preguntas distintas")


# Higiene entre runs

## Un director que arrastra la corrida anterior reparte puestos a fantasmas y
## fichas que nadie va a devolver. No tira error: se ve como enemigos que no
## atacan.
func test_reset_clears_everything() -> void:
	var enemy: Enemy = _brawler()
	CombatDirector.register(enemy)
	CombatDirector.request_attack_token(enemy)
	CombatDirector.claim_hazard(Vector3.ZERO)

	CombatDirector.reset()

	assert_eq(CombatDirector.get_active_enemies().size(), 0, "sin enemigos")
	assert_false(CombatDirector.holds_attack_token(enemy), "sin fichas")
	assert_false(CombatDirector.has_bearing(enemy), "sin puestos")
	assert_true(CombatDirector.claim_hazard(Vector3.ZERO), "sin reservas de piso")


func test_registering_twice_does_not_duplicate() -> void:
	var enemy: Enemy = _brawler()
	CombatDirector.register(enemy)
	CombatDirector.register(enemy)
	assert_eq(CombatDirector.get_active_enemies().size(), 1)


## Sin reparto, el rumbo sigue siendo el que dice el `.tres`. Es lo que sostiene a
## un enemigo en su primer frame, antes de que el director haya corrido.
func test_an_unassigned_enemy_falls_back_to_its_archetype() -> void:
	var enemy: Enemy = _brawler()
	enemy.data = load("res://data/enemies/bomber.tres")
	assert_eq(CombatDirector.bearing_for(enemy), enemy.data.approach_bearing_degrees)


func _brawler() -> Enemy:
	var enemy := Enemy.new()
	enemy.data = load("res://data/enemies/rusher.tres")
	enemy.is_active = true
	autofree(enemy)
	return enemy
