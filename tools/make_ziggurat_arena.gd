@tool
extends "res://tools/shipped_arena_builder.gd"
## The Ziggurat: la arena vertical. Run headless:
##   godot --headless --path . -s tools/make_ziggurat_arena.gd
##
## Donde The Pit reparte el terreno alto en un anillo y cinco islas, esta lo junta
## en un solo lugar: una piramide escalonada de tres terrazas en el centro de un
## piso abierto. Es rey de la colina. La cima ve toda la arena y baja por cuatro
## zip lines a cualquier lado; la horda sube por dos escaleras de saltos, una al
## oeste y otra al este, y desde el piso no hay donde esconderse de un tirador
## arriba salvo los pilares.
##
## Las terrazas son anillos, no losas: debajo de la cima queda un patio de nueve
## metros de alto con charcos, que es el atajo peligroso de un lado al otro. Una
## piramide maciza de losas finas dejaba un sotano de 18x18 celdas a 2m de alto,
## el mejor escondite de la arena.

## Cada terraza: primera celda y ancho del anillo. La primera es la ancha porque
## es donde aterrizan los zip lines; la segunda tiene dos celdas y no tres porque
## el cable baja dos alturas en cinco celdas, y con tres le pasaba por adentro.
const TIER_1_ORIGIN: int = 7
const TIER_1_WIDTH: int = 4
const TIER_2_ORIGIN: int = 11
const TIER_2_WIDTH: int = 2
## La cima, maciza.
const SUMMIT_ORIGIN: int = 13
const SUMMIT_SIZE: int = 6
## Las anclas cuelgan sobre el piso abierto a esta altura, y una mas sobre la cima.
const ANCHOR_LEVEL: int = 3
const SUMMIT_ANCHOR_LEVEL: int = 5


func _arena_name() -> String:
	return "The Ziggurat"


func _out_path() -> String:
	return "res://data/arenas/ziggurat_arena.tres"


func _build() -> void:
	_fill_floor(0, Vector2i.ZERO, Vector2i(FLOOR, FLOOR))
	_build_tiers()
	_build_climbs()
	_build_zip_lines()
	_build_perches()
	_build_cover()
	_build_courtyard()
	_build_anchors()
	_build_pickups()
	_build_spawns()


# Private

func _build_tiers() -> void:
	_floor_ring(1, TIER_1_ORIGIN, TIER_1_WIDTH)
	_floor_ring(2, TIER_2_ORIGIN, TIER_2_WIDTH)
	_fill_floor(3, Vector2i(SUMMIT_ORIGIN, SUMMIT_ORIGIN), Vector2i(SUMMIT_SIZE, SUMMIT_SIZE))
	# Parapetos en las esquinas de las dos terrazas: cobertura para el que sube,
	# lejos de las escaleras y de donde aterrizan los zip lines.
	for level: int in [1, 2]:
		var low: int = TIER_1_ORIGIN if level == 1 else TIER_2_ORIGIN
		var high: int = FLOOR - 1 - low
		for cell: Vector3i in [
			Vector3i(low, level, low), Vector3i(high, level, low),
			Vector3i(low, level, high), Vector3i(high, level, high),
		]:
			_decorate(&"cover_low", cell)


## Un anillo de `width` celdas de ancho, simetrico en la grilla, con la esquina
## en `origin`: dos franjas enteras al norte y al sur y dos cortas entre ellas.
## En baldosas de 2x2, que cubren justo los dos anchos que se usan.
func _floor_ring(level: int, origin: int, width: int) -> void:
	var side: int = FLOOR - 2 * origin
	var far: int = origin + side - width
	var inner: int = side - 2 * width
	_fill_floor(level, Vector2i(origin, origin), Vector2i(side, width), 2)
	_fill_floor(level, Vector2i(origin, far), Vector2i(side, width), 2)
	_fill_floor(level, Vector2i(origin, origin + width), Vector2i(width, inner), 2)
	_fill_floor(level, Vector2i(far, origin + width), Vector2i(width, inner), 2)


## Dos escaleras de saltos hasta la cima, la que usa la horda: tres links por
## lado, cada uno del borde de una terraza a la siguiente. El link es (0, +1, +2)
## sin rotar; un cuarto de vuelta lo manda a -X y tres a +X. Y escalones para el
## jugador en las otras dos caras, que el mantle sube solo.
func _build_climbs() -> void:
	_place(&"jump_link", Vector3i(5, 0, 14), 3)
	_place(&"jump_link", Vector3i(9, 1, 14), 3)
	_place(&"jump_link", Vector3i(12, 2, 14), 3)
	_place(&"jump_link", Vector3i(26, 0, 17), 1)
	_place(&"jump_link", Vector3i(22, 1, 17), 1)
	_place(&"jump_link", Vector3i(19, 2, 17), 1)
	for cell: Vector3i in [
		Vector3i(15, 1, 6), Vector3i(16, 1, 25), Vector3i(6, 1, 20), Vector3i(25, 1, 11),
		Vector3i(15, 2, 10), Vector3i(16, 2, 21), Vector3i(10, 2, 18), Vector3i(21, 2, 13),
		Vector3i(16, 3, 12), Vector3i(15, 3, 19),
	]:
		_place(&"ramp_1x1", cell)
	# Pads en el borde interior de la segunda terraza: suben derecho y la cima
	# esta a una celda, asi que retomarla es un salto y no una escalera entera.
	for cell: Vector3i in [
		Vector3i(12, 2, 17), Vector3i(19, 2, 14), Vector3i(14, 2, 12), Vector3i(17, 2, 19),
	]:
		_place(&"bounce_pad", cell)


## La salida de la cima: cuatro zip lines, uno por cara, que bajan dos alturas en
## cinco celdas y dejan en la primera terraza. Bajar es rapido y en una sola
## direccion; volver a subir cuesta.
func _build_zip_lines() -> void:
	_place(&"zip_line", Vector3i(15, 3, 13), 2)
	_place(&"zip_line", Vector3i(16, 3, 18), 0)
	_place(&"zip_line", Vector3i(13, 3, 16), 1)
	_place(&"zip_line", Vector3i(18, 3, 15), 3)


## Dos perchas sueltas en esquinas opuestas, sobre las puertas: la contra de la
## cima, desde donde se le tira al que esta arriba. El pad va al lado y no
## debajo, porque lanza derecho hacia arriba y la losa le haria de techo.
func _build_perches() -> void:
	_place(&"platform_2x2", Vector3i(3, 2, 3))
	_place(&"bounce_pad", Vector3i(5, 0, 4))
	_place(&"platform_2x2", Vector3i(27, 2, 27))
	_place(&"bounce_pad", Vector3i(26, 0, 27))


## El piso abierto alrededor de la piramide: pilares y cobertura baja dispersa.
## Pocos a proposito - es la galeria de tiro que la cima tiene que poder cubrir.
func _build_cover() -> void:
	for cell: Vector3i in [
		Vector3i(3, 0, 10), Vector3i(3, 0, 21), Vector3i(28, 0, 10), Vector3i(28, 0, 21),
		Vector3i(10, 0, 3), Vector3i(21, 0, 3), Vector3i(10, 0, 28), Vector3i(21, 0, 28),
	]:
		_decorate(&"pillar_1x1", cell)
	for cell: Vector3i in [
		Vector3i(2, 0, 7), Vector3i(2, 0, 24), Vector3i(29, 0, 7), Vector3i(29, 0, 24),
		Vector3i(7, 0, 2), Vector3i(24, 0, 2), Vector3i(7, 0, 29), Vector3i(24, 0, 29),
		Vector3i(5, 0, 16), Vector3i(26, 0, 15), Vector3i(16, 0, 5), Vector3i(15, 0, 26),
	]:
		_decorate(&"cover_low", cell)


## El patio debajo de la cima: cruzarlo es lo mas corto de un lado al otro, y
## cuesta vida.
func _build_courtyard() -> void:
	for cell: Vector3i in [
		Vector3i(14, 0, 14), Vector3i(17, 0, 14), Vector3i(14, 0, 17), Vector3i(17, 0, 17),
	]:
		_decorate(&"hazard_zone", cell)


func _build_anchors() -> void:
	for cell: Vector3i in [
		Vector3i(4, ANCHOR_LEVEL, 4), Vector3i(27, ANCHOR_LEVEL, 4),
		Vector3i(4, ANCHOR_LEVEL, 27), Vector3i(27, ANCHOR_LEVEL, 27),
		Vector3i(3, ANCHOR_LEVEL, 16), Vector3i(28, ANCHOR_LEVEL, 15),
		Vector3i(16, ANCHOR_LEVEL, 3), Vector3i(15, ANCHOR_LEVEL, 28),
		Vector3i(15, SUMMIT_ANCHOR_LEVEL, 15),
	]:
		_place(&"grapple_anchor", cell)


func _build_pickups() -> void:
	for cell: Vector3i in [
		Vector3i(4, 0, 13), Vector3i(27, 0, 18), Vector3i(13, 0, 27), Vector3i(18, 0, 4),
		Vector3i(8, 1, 8), Vector3i(23, 1, 23), Vector3i(8, 1, 23), Vector3i(23, 1, 8),
		Vector3i(12, 2, 11), Vector3i(19, 2, 20),
		Vector3i(14, 3, 17), Vector3i(17, 3, 14),
	]:
		_decorate(&"ammo_pickup", cell)


## Siete, porque las waves nombran door_01 a door_07 y el loader las numera en
## este orden. Todas en el piso de afuera: la horda arranca abajo y la piramide
## es lo que tiene que subir.
func _build_spawns() -> void:
	_model.set_player_spawn(Vector3i(12, 0, 28))
	var last: int = FLOOR - 1
	var mid: int = int(FLOOR / 2.0)
	for cell: Vector3i in [
		Vector3i(0, 0, mid), Vector3i(last, 0, mid),
		Vector3i(mid, 0, 0), Vector3i(mid, 0, last),
		Vector3i(0, 0, 0), Vector3i(last, 0, last), Vector3i(0, 0, last),
	]:
		_model.add_enemy_spawn(cell)
