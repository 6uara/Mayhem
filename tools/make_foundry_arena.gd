@tool
extends "res://tools/shipped_arena_builder.gd"
## The Foundry: la arena de corta distancia. Run headless:
##   godot --headless --path . -s tools/make_foundry_arena.gd
##
## Las otras dos son abiertas y se pelean de lejos; esta corta la vista. El piso
## esta partido por muros en doce cuartos alrededor de una nave central, todos
## con puertas de dos celdas, asi que ninguna linea de tiro pasa de un cuarto.
## La horda entra por las puertas de carga de los cuartos de afuera y llega por
## los pasillos, de cerca y por varios lados a la vez.
##
## Arriba de la nave hay una pasarela: un anillo con un centro y cuatro brazos,
## al nivel 1. Cada lado del anillo tiene una plataforma que se cae al pisarla,
## que es el atajo que se paga. Abajo, el piso de la nave tiene charcos en las
## esquinas y campos lentos en cada entrada: el lugar donde frenar es donde la
## horda te alcanza.

## Las lineas de muro. Las de afuera de la nave cortan solo el anillo de cuartos.
const HALL_MIN: int = 8
const HALL_MAX: int = 24
const ROOM_SPLIT: int = 16
## Las puertas de cada tramo de muro, en el medio de cada cuarto.
const DOORWAYS: Array[int] = [3, 4, 11, 12, 19, 20, 27, 28]
## Las anclas de los cuartos cuelgan una altura por encima de los muros, y las de
## la nave una mas, por encima de las gruas.
const ROOM_ANCHOR_LEVEL: int = 2
const HALL_ANCHOR_LEVEL: int = 3


func _arena_name() -> String:
	return "The Foundry"


func _out_path() -> String:
	return "res://data/arenas/foundry_arena.tres"


func _build() -> void:
	_fill_floor(0, Vector2i.ZERO, Vector2i(FLOOR, FLOOR))
	_build_walls()
	_build_gantry()
	_build_cranes()
	_build_hazards()
	_build_cover()
	_build_anchors()
	_build_pickups()
	_build_spawns()


# Private

## Las lineas en Z son duenias de los cruces: las de X saltean esas celdas, si no
## los dos muros pedirian la misma.
func _build_walls() -> void:
	var last: int = FLOOR - 1
	for line: int in [HALL_MIN, HALL_MAX]:
		_wall_run(line, 0, last, false, DOORWAYS)
		var gaps: Array[int] = DOORWAYS.duplicate()
		gaps.append_array([HALL_MIN, HALL_MAX])
		_wall_run(line, 0, last, true, gaps)
	# La division de los cuartos del medio de cada lado: solo afuera de la nave.
	_wall_run(ROOM_SPLIT, 0, HALL_MIN - 1, true, [3, 4] as Array[int])
	_wall_run(ROOM_SPLIT, HALL_MAX + 1, last, true, [27, 28] as Array[int])
	_wall_run(ROOM_SPLIT, 0, HALL_MIN - 1, false, [3, 4] as Array[int])
	_wall_run(ROOM_SPLIT, HALL_MAX + 1, last, false, [27, 28] as Array[int])


## La pasarela: un centro de 3x3, cuatro brazos de tres celdas y un anillo de
## 11x11 que los une. Cada lado del anillo son tres tramos de catwalk y una
## plataforma que se cae; el `catwalk_1x3` corre en +Z sin girar y en +X con
## tres cuartos de vuelta.
func _build_gantry() -> void:
	_place(&"floor_3x3", Vector3i(15, 1, 15))
	_place(&"catwalk_1x3", Vector3i(16, 1, 12))
	_place(&"catwalk_1x3", Vector3i(16, 1, 18))
	_place(&"catwalk_1x3", Vector3i(12, 1, 16), 3)
	_place(&"catwalk_1x3", Vector3i(18, 1, 16), 3)
	# Norte, de oeste a este.
	for x: int in [11, 14, 17]:
		_place(&"catwalk_1x3", Vector3i(x, 1, 11), 3)
	_place(&"disappearing_platform", Vector3i(20, 1, 11))
	# Este, de norte a sur.
	for z: int in [11, 14, 17]:
		_place(&"catwalk_1x3", Vector3i(21, 1, z))
	_place(&"disappearing_platform", Vector3i(21, 1, 20))
	# Sur, de oeste a este.
	_place(&"disappearing_platform", Vector3i(12, 1, 21))
	for x: int in [13, 16, 19]:
		_place(&"catwalk_1x3", Vector3i(x, 1, 21), 3)
	# Oeste, de norte a sur.
	for z: int in [12, 15, 18]:
		_place(&"catwalk_1x3", Vector3i(11, 1, z))
	_place(&"disappearing_platform", Vector3i(11, 1, 21))

	# Por donde sube la horda: cuatro links al anillo, uno por lado, y dos al
	# centro. El link es (0, +1, +2) sin rotar.
	_place(&"jump_link", Vector3i(14, 0, 9), 0)
	_place(&"jump_link", Vector3i(18, 0, 23), 2)
	_place(&"jump_link", Vector3i(9, 0, 18), 3)
	_place(&"jump_link", Vector3i(23, 0, 14), 1)
	_place(&"jump_link", Vector3i(13, 0, 15), 3)
	_place(&"jump_link", Vector3i(19, 0, 17), 1)
	# Escalones para el jugador, del lado de afuera del anillo.
	for cell: Vector3i in [
		Vector3i(16, 1, 10), Vector3i(15, 1, 22), Vector3i(10, 1, 15), Vector3i(22, 1, 16),
	]:
		_place(&"ramp_1x1", cell)


## Dos gruas arriba de la nave, al nivel 2: lo unico de la arena desde donde se
## ve mas de un cuarto. El pad va al lado de la losa y no debajo, porque lanza
## derecho hacia arriba.
func _build_cranes() -> void:
	_place(&"platform_2x2", Vector3i(13, 2, 13))
	_place(&"bounce_pad", Vector3i(15, 0, 13))
	_place(&"platform_2x2", Vector3i(18, 2, 18))
	_place(&"bounce_pad", Vector3i(17, 0, 19))


func _build_hazards() -> void:
	# Las esquinas de la nave, que quedan afuera del anillo.
	for cell: Vector3i in [
		Vector3i(10, 0, 10), Vector3i(22, 0, 10), Vector3i(10, 0, 22), Vector3i(22, 0, 22),
		Vector3i(4, 0, 20), Vector3i(27, 0, 12), Vector3i(12, 0, 4), Vector3i(20, 0, 27),
	]:
		_place(&"hazard_zone", cell)
	# Un campo lento del lado de adentro de una puerta de cada muro de la nave.
	for cell: Vector3i in [
		Vector3i(9, 0, 19), Vector3i(23, 0, 12), Vector3i(12, 0, 9), Vector3i(20, 0, 23),
		Vector3i(27, 0, 4), Vector3i(4, 0, 27),
	]:
		_place(&"snare_zone", cell)


## Cada cuarto con su cobertura, corrida de la puerta para no tapar el paso, y
## pilares en la nave para cortar lo que la pasarela deja ver.
func _build_cover() -> void:
	for room_x: int in [0, 1, 2, 3]:
		for room_z: int in [0, 1, 2, 3]:
			if room_x in [1, 2] and room_z in [1, 2]:
				continue  # La nave.
			var origin := Vector2i(room_x * 8, room_z * 8)
			_decorate(&"cover_low", Vector3i(origin.x + 2, 0, origin.y + 6))
			_decorate(&"cover_low", Vector3i(origin.x + 6, 0, origin.y + 2))
			_decorate(&"cover_low", Vector3i(origin.x + 5, 0, origin.y + 6))
	for cell: Vector3i in [
		Vector3i(19, 0, 13), Vector3i(13, 0, 19), Vector3i(10, 0, 13), Vector3i(22, 0, 19),
	]:
		_decorate(&"pillar_1x1", cell)


func _build_anchors() -> void:
	for cell: Vector3i in [
		Vector3i(4, ROOM_ANCHOR_LEVEL, 4), Vector3i(27, ROOM_ANCHOR_LEVEL, 4),
		Vector3i(4, ROOM_ANCHOR_LEVEL, 27), Vector3i(27, ROOM_ANCHOR_LEVEL, 27),
		Vector3i(12, HALL_ANCHOR_LEVEL, 12), Vector3i(20, HALL_ANCHOR_LEVEL, 12),
		Vector3i(12, HALL_ANCHOR_LEVEL, 20), Vector3i(20, HALL_ANCHOR_LEVEL, 20),
	]:
		_place(&"grapple_anchor", cell)


func _build_pickups() -> void:
	for cell: Vector3i in [
		Vector3i(5, 0, 13), Vector3i(26, 0, 18), Vector3i(13, 0, 26), Vector3i(18, 0, 5),
		Vector3i(3, 0, 3), Vector3i(28, 0, 28),
		Vector3i(16, 1, 16), Vector3i(11, 1, 11), Vector3i(21, 1, 21),
		Vector3i(14, 2, 14), Vector3i(19, 2, 19),
	]:
		_decorate(&"ammo_pickup", cell)


## Siete puertas de carga, una por cuarto de afuera y ninguna sobre un muro. Las
## dos primeras son las de la wave 1, en lados opuestos.
func _build_spawns() -> void:
	_model.set_player_spawn(Vector3i(14, 0, 19))
	var last: int = FLOOR - 1
	for cell: Vector3i in [
		Vector3i(0, 0, 12), Vector3i(last, 0, 20),
		Vector3i(12, 0, 0), Vector3i(20, 0, last),
		Vector3i(0, 0, 0), Vector3i(last, 0, last), Vector3i(0, 0, last),
	]:
		_model.add_enemy_spawn(cell)
