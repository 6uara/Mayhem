extends GutTest
## El publico en las gradas.
##
## Tres cosas tienen que ser ciertas y ninguna se ve mirando la pantalla: que la
## misma arena de siempre la misma multitud, que ningun espectador termine
## parado adentro del area de juego, y que `pick_seat()` - de donde van a salir
## los gadgets que caen a la arena - devuelva siempre un punto de la tribuna.

const BOUNDS := AABB(Vector3(-4.0, 0.0, -4.0), Vector3(64.0, 20.0, 64.0))
const PIT_MARGIN: float = 4.0


func _crowd() -> CrowdStands:
	var crowd := CrowdStands.new()
	add_child_autofree(crowd)
	return crowd


## Los asientos salen de `get_seats()` y no del MultiMesh a proposito: headless
## corre con el servidor de render dummy, que acepta las transformadas de
## instancia y despues las devuelve todas en cero.
func _seats(crowd: CrowdStands) -> PackedVector3Array:
	return crowd.get_seats()


func test_populating_seats_the_stands() -> void:
	var crowd: CrowdStands = _crowd()
	crowd.populate(BOUNDS, PIT_MARGIN)
	assert_gt(crowd.get_seat_count(), 100, "una arena de 64m tiene tribuna de sobra")
	assert_eq(crowd.multimesh.instance_count, crowd.get_seat_count(),
		"un asiento sembrado es una instancia dibujada")
	assert_true(crowd.has_seats())


func test_the_same_arena_always_gets_the_same_crowd() -> void:
	# La semilla sale del tamaño de la arena a proposito: un publico que se
	# reordena entre una carga y la siguiente se lee como un bug.
	var first: CrowdStands = _crowd()
	first.populate(BOUNDS, PIT_MARGIN)
	var second: CrowdStands = _crowd()
	second.populate(BOUNDS, PIT_MARGIN)
	assert_eq(second.get_seat_count(), first.get_seat_count())
	assert_eq(_seats(second), _seats(first), "mismo tamaño, misma multitud")


func test_a_different_arena_gets_a_different_crowd() -> void:
	var small: CrowdStands = _crowd()
	small.populate(AABB(Vector3.ZERO, Vector3(32.0, 20.0, 32.0)), PIT_MARGIN)
	var big: CrowdStands = _crowd()
	big.populate(AABB(Vector3.ZERO, Vector3(96.0, 20.0, 96.0)), PIT_MARGIN)
	assert_gt(big.get_seat_count(), small.get_seat_count(),
		"mas perimetro, mas gente")


func test_nobody_is_standing_in_the_arena() -> void:
	# El foso ya separa la tribuna del area de juego; esto es lo que atrapa un
	# `first_row_offset` o un `pit_margin` que se hayan ido a negativo.
	var crowd: CrowdStands = _crowd()
	crowd.populate(BOUNDS, PIT_MARGIN)
	var play_area := Rect2(
		Vector2(BOUNDS.position.x, BOUNDS.position.z),
		Vector2(BOUNDS.size.x, BOUNDS.size.z))
	for seat: Vector3 in _seats(crowd):
		assert_false(play_area.has_point(Vector2(seat.x, seat.z)),
			"un espectador en %v cayo adentro de la arena" % seat)


func test_the_stands_climb_away_from_the_arena() -> void:
	var crowd: CrowdStands = _crowd()
	crowd.populate(BOUNDS, PIT_MARGIN)
	var floor_y: float = BOUNDS.position.y
	var highest: float = floor_y
	for seat: Vector3 in _seats(crowd):
		assert_gt(seat.y, floor_y, "nadie por debajo del piso de la arena")
		highest = maxf(highest, seat.y)
	assert_gt(highest, floor_y + crowd.row_rise,
		"la ultima fila esta mas arriba que la primera")


func test_drops_come_from_a_seat_in_the_front_rows() -> void:
	var crowd: CrowdStands = _crowd()
	crowd.populate(BOUNDS, PIT_MARGIN)
	var seats: PackedVector3Array = _seats(crowd)
	# Solo las dos primeras filas: es de donde un brazo llega a la arena.
	var front_ceiling: float = BOUNDS.position.y + crowd.row_rise * 2.0
	for i: int in 40:
		var seat: Vector3 = crowd.pick_seat()
		assert_true(seats.has(seat), "%v no es un asiento de esta tribuna" % seat)
		assert_lt(seat.y, front_ceiling + crowd.seat_height,
			"%v esta demasiado arriba para tirar algo a la arena" % seat)


func test_an_empty_crowd_answers_instead_of_crashing() -> void:
	# Quien pregunta tiene que chequear has_seats(), pero una tribuna vacia no
	# puede ser la causa de que se caiga un director de drops.
	var crowd: CrowdStands = _crowd()
	crowd.rows = 0
	crowd.populate(BOUNDS, PIT_MARGIN)
	assert_false(crowd.has_seats())
	assert_eq(crowd.pick_seat(), Vector3.ZERO)
