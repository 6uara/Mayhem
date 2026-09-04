extends GutTest
## El coliseo generado.
##
## Lo que hay que sostener no es como se ve: es que la forma no se meta en el
## area de juego, que la tribuna trepe, y sobre todo que las filas de asientos
## sean las huellas de verdad. Eso ultimo es el motivo entero de generar la
## geometria en vez de repetir un modelo - si las filas vuelven a ser una
## estimacion, no se gano nada.

const SHELL_SCENE: String = "res://scenes/arena/shells/coliseum_shell.tscn"
const BOUNDS := AABB(Vector3(-6.0, 0.0, -6.0), Vector3(72.0, 20.0, 72.0))


func _shell() -> ArenaColiseum:
	var scene := load(SHELL_SCENE) as PackedScene
	var shell := scene.instantiate() as ArenaColiseum
	add_child_autofree(shell)
	return shell


func _built(shell: ArenaColiseum) -> ArenaColiseum:
	shell.setup(BOUNDS)
	return shell


func _play_area() -> Rect2:
	return Rect2(
		Vector2(BOUNDS.position.x, BOUNDS.position.z),
		Vector2(BOUNDS.size.x, BOUNDS.size.z))


func test_the_bowl_is_one_mesh() -> void:
	# Un coliseo entero en una malla: lo que costaria caro no son los triangulos
	# sino miles de nodos, y este venue no tiene ninguno que valga la pena.
	var shell: ArenaColiseum = _built(_shell())
	var bowl := shell.get_node("Coliseum/Bowl") as MeshInstance3D
	assert_not_null(bowl)
	assert_gt(bowl.mesh.get_surface_count(), 0)


func test_the_stands_never_reach_into_the_arena() -> void:
	# El unico error de esta forma que el jugador *siente* en vez de ver: un
	# ovalo que corta las esquinas del area de juego le come metros de piso.
	var shell: ArenaColiseum = _built(_shell())
	var play: Rect2 = _play_area()
	for row: Dictionary in shell.get_seat_rows():
		for point: Vector3 in row["path"] as PackedVector3Array:
			assert_false(play.has_point(Vector2(point.x, point.z)),
				"la grada se metio en la arena, en %v" % point)


func test_a_long_arena_gets_a_long_oval() -> void:
	# La planta sigue a la arena. Un rectangulo alargado adentro de un ovalo
	# redondo dejaria un foso absurdo en los lados largos.
	var shell: ArenaColiseum = _shell()
	shell.setup(AABB(Vector3.ZERO, Vector3(120.0, 20.0, 40.0)))
	var first: PackedVector3Array = shell.get_seat_rows()[0]["path"]
	var reach := Vector2.ZERO
	for point: Vector3 in first:
		reach.x = maxf(reach.x, absf(point.x - 60.0))
		reach.y = maxf(reach.y, absf(point.z - 20.0))
	assert_gt(reach.x, reach.y * 1.5, "el ovalo se estira con la arena")


func test_every_row_wraps_the_one_below_it() -> void:
	# Es lo unico que la tribuna necesita que sea cierto del ovalo: que cada fila
	# envuelva a la anterior. Sin eso una fila se mete en la de adelante y la
	# gente queda dentro del escalon.
	var shell: ArenaColiseum = _built(_shell())
	var rows: Array[Dictionary] = shell.get_seat_rows()
	assert_gt(rows.size(), 10)
	var previous: float = 0.0
	for row: Dictionary in rows:
		var widest: float = 0.0
		for point: Vector3 in row["path"] as PackedVector3Array:
			widest = maxf(widest, absf(point.x - 30.0))
		assert_gt(widest, previous, "una fila que no envuelve a la de abajo")
		previous = widest


func test_the_stands_climb() -> void:
	var shell: ArenaColiseum = _built(_shell())
	var rows: Array[Dictionary] = shell.get_seat_rows()
	var lowest: float = (rows[0]["path"] as PackedVector3Array)[0].y
	var highest: float = (rows[rows.size() - 1]["path"] as PackedVector3Array)[0].y
	assert_gte(lowest, BOUNDS.position.y + shell.podium_height,
		"nadie se sienta por debajo del podio")
	assert_gt(highest - lowest, 20.0, "tres anillos tienen que trepar de verdad")


func test_there_is_one_row_per_step() -> void:
	# Las filas no son una estimacion repartida sobre una rampa: son las huellas
	# que genero el mismo bucle. Si esto deja de dar exacto es que alguien volvio
	# a estimar.
	var shell: ArenaColiseum = _shell()
	shell.tiers = 4
	shell.rows_per_tier = 6
	shell.setup(BOUNDS)
	assert_eq(shell.get_seat_rows().size(), 24)


func test_each_row_is_a_closed_loop() -> void:
	var shell: ArenaColiseum = _built(_shell())
	for row: Dictionary in shell.get_seat_rows():
		var path: PackedVector3Array = row["path"]
		assert_eq(path.size(), shell.segments + 1, "una vuelta entera")
		assert_almost_eq(path[0].distance_to(path[path.size() - 1]), 0.0, 0.001,
			"la vuelta tiene que cerrar")


func test_the_crowd_gets_seated_on_the_real_treads() -> void:
	# El paso entero existe para esto.
	var shell: ArenaColiseum = _built(_shell())
	var crowd := shell.get_node("Crowd") as CrowdStands
	assert_not_null(crowd)
	assert_gt(crowd.get_seat_count(), 500, "un coliseo tiene que estar lleno")

	var row_heights: Array[float] = []
	for row: Dictionary in shell.get_seat_rows():
		var y: float = (row["path"] as PackedVector3Array)[0].y
		if not row_heights.has(y):
			row_heights.append(y)
	for seat: Vector3 in crowd.get_seats():
		assert_true(row_heights.has(seat.y),
			"un espectador en %v no esta sobre ninguna huella" % seat)


func test_the_arena_is_still_walled_the_way_it_always_was() -> void:
	# Lo que cambia en este venue es lo que se ve, no lo que se choca.
	var shell: ArenaColiseum = _built(_shell())
	var perimeter := shell.get_node("Perimeter")
	assert_eq(perimeter.get_child_count(), 4)
	for child: Node in perimeter.get_children():
		assert_true(child is StaticBody3D)


func test_rebuilding_does_not_stack_two_coliseums() -> void:
	var shell: ArenaColiseum = _built(_shell())
	var before: int = shell.get_seat_rows().size()
	shell.setup(BOUNDS)
	await wait_frames(2)
	assert_eq(shell.get_seat_rows().size(), before, "no se acumulan filas")
	var bowls: int = 0
	for child: Node in shell.get_children():
		if child.name.begins_with("Coliseum") and not child.is_queued_for_deletion():
			bowls += 1
	assert_eq(bowls, 1, "un solo cuenco")


# El acabado

func test_the_bowl_wears_the_same_panel_as_the_rest_of_the_game() -> void:
	# Se reusa arena_glitch_panel en vez de escribir un shader propio: un coliseo
	# con su propio look seria un segundo lenguaje visual para el mismo juego.
	var shell: ArenaColiseum = _built(_shell())
	var bowl := shell.get_node("Coliseum/Bowl") as MeshInstance3D
	var material := bowl.material_override as ShaderMaterial
	assert_not_null(material, "el cuenco va con el panel del proyecto")
	assert_eq(material.shader.resource_path, ArenaColiseum.PANEL_SHADER)


func test_there_is_a_lit_edge_per_walkway_plus_the_podium() -> void:
	# El acabado cyberpunk no es geometria: es esta linea. Un filo por remate de
	# pasillo, mas el del podio.
	var shell: ArenaColiseum = _shell()
	shell.tiers = 3
	shell.setup(BOUNDS)
	assert_eq(shell._trim_levels.size(), 3, "el podio y los dos pasillos")
	assert_not_null(shell.get_node("Coliseum/Trim"))


func test_the_lit_edge_does_not_fight_the_wall_it_lights() -> void:
	# Dos caras en el mismo plano pelean por cada pixel y el filo titila.
	var shell: ArenaColiseum = _built(_shell())
	assert_gt(shell.trim_offset, 0.0)


func test_the_house_gets_its_screens() -> void:
	var shell: ArenaColiseum = _built(_shell())
	var screens := shell.get_node("Coliseum/Screens")
	assert_eq(screens.get_child_count(), shell.screens)
	for child: Node in screens.get_children():
		var mesh := child as MeshInstance3D
		assert_gt(mesh.position.y, shell.get_rim_height(),
			"las pantallas van sobre el ultimo anillo")
