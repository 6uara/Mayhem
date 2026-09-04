@tool
extends SceneTree
## Builds the arena a normal run happens in, with the same PlacementModel the
## editor uses. Run headless:
##   godot --headless --path . -s tools/make_default_arena.gd
##
## The greybox arena it replaces was a hand-built scene; this is data, so it can
## be opened in the arena editor, played, and changed without touching a scene
## file. What it keeps from the greybox is the shape of the fight: a wide floor,
## two raised levels reached by ramps and pads, cover to break sightlines, and
## seven spawn doors spread so no camping spot covers them all.
##
## Re-autorada al tamano fijo de 32x8x32. La version anterior construia 18x18
## celdas dentro de una grilla de 24: el piso llegaba a 72m y el resto era vacio
## que ni las gradas enmarcaban. Ahora la grilla es una sola y el piso la llena
## entera, 128m de lado, con el vacio interior repartido en un anillo elevado,
## cuatro islas y cuatro perchas en vez de en un borde muerto.

const CATALOG_PATH: String = "res://data/arena_pieces/default_catalog.tres"
const OUT_PATH: String = "res://data/arenas/default_arena.tres"

## El unico tamano que hay. 32x32 celdas de 4m: un piso de 128m.
const GRID: Vector3i = ArenaData.FIXED_SIZE
## Cuantas celdas del lado construye el piso. Igual a la grilla a proposito: el
## contenido *es* la arena, y lo que sobra de grilla no lo enmarca nadie. Bajarlo
## es la unica perilla para achicar la cancha sin tocar el resto del script.
const FLOOR: int = 32
## El anillo elevado, una altura arriba.
const LEDGE_LEVEL: int = 1
## Las perchas, dos arriba, a las que se llega por pad.
const PERCH_LEVEL: int = 2
## Las anclas del grapple cuelgan una altura sobre las perchas.
const ANCHOR_LEVEL: int = 3

## Primera celda del anillo y cuantos bloques de 3x3 tiene de lado.
const RING_ORIGIN: int = 2
const RING_BLOCKS: int = 9
## Donde empieza y termina el hueco central que el anillo rodea.
const INNER_MIN: int = 5
const INNER_MAX: int = 25

var _model: PlacementModel
var _failures: int = 0
var _skipped: int = 0


func _initialize() -> void:
	var catalog := load(CATALOG_PATH) as PieceCatalog
	if catalog == null:
		push_error("make_default_arena: no catalog at %s" % CATALOG_PATH)
		quit(1)
		return

	var arena := ArenaData.new()
	arena.arena_name = "The Pit"
	arena.grid_size = GRID
	arena.theme_id = &"coliseum"
	arena.author = "mayhem"
	arena.created_at = Time.get_datetime_string_from_system(true)
	_model = PlacementModel.new(arena, catalog)

	_build_floor()
	_build_ring()
	_build_islands()
	_build_perches()
	_build_cover()
	_build_traversal()
	_build_pickups()
	_build_spawns()

	if _failures > 0:
		push_error("%d placements were refused; the arena is not what this script says" % _failures)
		quit(1)
		return

	var issues: Array[ValidationIssue] = ArenaValidator.validate(arena, catalog)
	for issue: ValidationIssue in issues:
		print("%s %s: %s" % [
			"ERROR " if issue.is_error() else "WARN  ", issue.code, issue.message])
	if not ArenaValidator.errors(issues).is_empty():
		push_error("make_default_arena: the arena does not validate")
		quit(1)
		return

	var graph: GridGraph = GridGraph.build(arena, catalog)
	print("pieces: %d | skipped decor: %d | walkable: %d | enemy spawns: %d | nav links: %d" % [
		arena.placements.size(), _skipped, graph.walkable_cells().size(),
		arena.enemy_spawns.size(), graph.shared_links().size()])
	var error: Error = ArenaIO.save(arena, OUT_PATH)
	print("saved %s (%d)" % [OUT_PATH, error])
	quit(0 if error == OK else 1)


# Private

## Placing through here rather than `model.place` directly: a refusal used to be
## a silently missing piece, and an arena that quietly lost its anchors still
## saved and still validated. Now the build fails and says which cell.
func _place(piece_id: StringName, cell: Vector3i, rotation: int = 0) -> void:
	var refusal: StringName = _model.refusal_for(piece_id, cell, rotation)
	if refusal != &"":
		push_error("%s at %s refused: %s" % [piece_id, cell, refusal])
		_failures += 1


## Para la decoracion que se reparte por formula - cobertura, munición, charcos.
## Que una de esas caiga sobre un pad ya puesto no es un error del layout, es el
## precio de repartirlas con un `for`: se saltea y se cuenta. Cualquier otro
## motivo de rechazo sigue siendo un error, porque ya no es una coincidencia.
func _decorate(piece_id: StringName, cell: Vector3i, rotation: int = 0) -> void:
	var refusal: StringName = _model.refusal_for(piece_id, cell, rotation)
	if refusal == &"":
		return
	if refusal == &"cell_taken":
		_skipped += 1
		return
	push_error("%s at %s refused: %s" % [piece_id, cell, refusal])
	_failures += 1


## El piso entero, en bloques de 3x3 con dos tiras de 2x2 para el resto.
##
## Un piso de 32x32 en `floor_1x1` son 1024 StaticBody con su malla, y el
## contenido es el mismo: una losa. Los bloques grandes lo bajan a 131 piezas.
func _build_floor() -> void:
	var blocks: int = int(FLOOR / 3.0)
	var tiled: int = blocks * 3
	for x: int in range(0, tiled, 3):
		for z: int in range(0, tiled, 3):
			_place(&"floor_3x3", Vector3i(x, 0, z))
	for z: int in range(0, FLOOR, 2):
		for x: int in range(tiled, FLOOR, 2):
			_place(&"floor_2x2", Vector3i(x, 0, z))
	for x: int in range(0, tiled, 2):
		for z: int in range(tiled, FLOOR, 2):
			_place(&"floor_2x2", Vector3i(x, 0, z))


## El anillo: una pasarela de tres celdas de ancho una altura arriba, que rodea
## el hueco central. Es la ruta alta que le da sentido al grapple y a las rampas,
## y el borde desde donde se ve entrar a la horda por las puertas de abajo.
func _build_ring() -> void:
	for i: int in RING_BLOCKS:
		for j: int in RING_BLOCKS:
			if i != 0 and i != RING_BLOCKS - 1 and j != 0 and j != RING_BLOCKS - 1:
				continue
			_place(&"floor_3x3", Vector3i(
				RING_ORIGIN + i * 3, LEDGE_LEVEL, RING_ORIGIN + j * 3))
	# Rampas al anillo, pegadas a su borde interior: cuatro en el medio de cada
	# lado y cuatro en las esquinas, para que subir nunca sea cruzar la arena.
	var mid: int = int(FLOOR / 2.0)
	for cell: Vector3i in [
		Vector3i(INNER_MIN, LEDGE_LEVEL, mid), Vector3i(INNER_MAX, LEDGE_LEVEL, mid),
		Vector3i(mid, LEDGE_LEVEL, INNER_MIN), Vector3i(mid, LEDGE_LEVEL, INNER_MAX),
		Vector3i(INNER_MIN, LEDGE_LEVEL, INNER_MIN),
		Vector3i(INNER_MAX, LEDGE_LEVEL, INNER_MIN),
		Vector3i(INNER_MIN, LEDGE_LEVEL, INNER_MAX),
		Vector3i(INNER_MAX, LEDGE_LEVEL, INNER_MAX),
	]:
		_place(&"ramp_1x1", cell)
	# Baranda sobre la fila exterior nada mas, para que nunca corte el paso.
	var outer: int = RING_ORIGIN + (RING_BLOCKS - 1) * 3 + 2
	for i: int in range(RING_ORIGIN, outer + 1, 3):
		_decorate(&"cover_low", Vector3i(i, LEDGE_LEVEL, RING_ORIGIN))
		_decorate(&"cover_low", Vector3i(i, LEDGE_LEVEL, outer))
		if i == RING_ORIGIN or i == outer:
			continue
		_decorate(&"cover_low", Vector3i(RING_ORIGIN, LEDGE_LEVEL, i))
		_decorate(&"cover_low", Vector3i(outer, LEDGE_LEVEL, i))


## Cuatro islas y una central, a la altura del anillo pero sin tocarlo: son el
## terreno alto del medio, y cada una tiene su rampa. Sin ellas el hueco que el
## anillo rodea son 84m de piso plano.
func _build_islands() -> void:
	for cell: Vector3i in _island_origins():
		_place(&"floor_3x3", cell)
	for cell: Vector3i in [
		Vector3i(8, LEDGE_LEVEL, 10), Vector3i(19, LEDGE_LEVEL, 10),
		Vector3i(8, LEDGE_LEVEL, 21), Vector3i(19, LEDGE_LEVEL, 21),
		Vector3i(14, LEDGE_LEVEL, 16),
	]:
		_place(&"ramp_1x1", cell)


func _island_origins() -> Array[Vector3i]:
	return [
		Vector3i(9, LEDGE_LEVEL, 9), Vector3i(20, LEDGE_LEVEL, 9),
		Vector3i(9, LEDGE_LEVEL, 20), Vector3i(20, LEDGE_LEVEL, 20),
		Vector3i(15, LEDGE_LEVEL, 15),
	]


## Las perchas: cuatro plataformas sueltas dos alturas arriba, cada una sobre su
## pad. Terreno alto que se gana y se pierde, y que no conecta con nada - bajarse
## es saltar, que es exactamente lo que las hace una decision y no un refugio.
func _build_perches() -> void:
	for cell: Vector3i in _perch_origins():
		_place(&"platform_2x2", cell)
		# El pad aterriza en la celda origen, asi que la cobertura va en la
		# diagonal: tapar el destino del link seria dejar la percha sin acceso.
		_decorate(&"cover_low", cell + Vector3i(1, 0, 1))
		_place(&"bounce_pad", Vector3i(cell.x, 0, cell.z))


func _perch_origins() -> Array[Vector3i]:
	return [
		Vector3i(12, PERCH_LEVEL, 6), Vector3i(24, PERCH_LEVEL, 12),
		Vector3i(6, PERCH_LEVEL, 18), Vector3i(18, PERCH_LEVEL, 24),
	]


## Cobertura repartida por el piso, mas dos muros cortos y cuatro pilares: un
## piso de 128m sin nada encima es una galeria de tiro de punta a punta.
func _build_cover() -> void:
	for x: int in range(5, FLOOR - 4, 5):
		for z: int in range(5, FLOOR - 4, 5):
			_decorate(&"cover_low", Vector3i(x, 0, z))
	for cell: Vector3i in [
		Vector3i(10, 0, 16), Vector3i(21, 0, 16),
		Vector3i(16, 0, 10), Vector3i(16, 0, 21),
	]:
		_decorate(&"pillar_1x1", cell)
	for z: int in range(12, 16):
		_decorate(&"wall_1x1", Vector3i(13, 0, z))
	for z: int in range(17, 21):
		_decorate(&"wall_1x1", Vector3i(18, 0, z))
	for cell: Vector3i in [
		Vector3i(8, 0, 8), Vector3i(23, 0, 8), Vector3i(8, 0, 23), Vector3i(23, 0, 23),
		Vector3i(13, 0, 19), Vector3i(18, 0, 13),
	]:
		_decorate(&"hazard_zone", cell)


## Links que la horda tambien puede usar, y anclas para el grapple.
func _build_traversal() -> void:
	# Uno por lado, rotado para que cada uno aterrice en el anillo que tiene
	# detras: el link es (0, +1, +2) sin rotar, y un cuarto de vuelta lo mueve.
	var mid: int = int(FLOOR / 2.0)
	_place(&"jump_link", Vector3i(mid, 0, 6), 2)
	_place(&"jump_link", Vector3i(mid, 0, FLOOR - 8), 0)
	_place(&"jump_link", Vector3i(6, 0, mid), 1)
	_place(&"jump_link", Vector3i(FLOOR - 8, 0, mid), 3)
	for cell: Vector3i in [
		Vector3i(11, 0, 11), Vector3i(21, 0, 21),
	]:
		_decorate(&"moving_platform", cell)
	# Las anclas cuelgan sobre piso abierto, una altura sobre las perchas: lo que
	# hace util a una es estar arriba tuyo, asi que van en celdas vacias.
	for cell: Vector3i in [
		Vector3i(9, ANCHOR_LEVEL, 9), Vector3i(22, ANCHOR_LEVEL, 9),
		Vector3i(9, ANCHOR_LEVEL, 22), Vector3i(22, ANCHOR_LEVEL, 22),
		Vector3i(16, ANCHOR_LEVEL, 6), Vector3i(16, ANCHOR_LEVEL, 26),
		Vector3i(6, ANCHOR_LEVEL, 16), Vector3i(26, ANCHOR_LEVEL, 16),
		Vector3i(16, ANCHOR_LEVEL + 1, 16),
	]:
		_place(&"grapple_anchor", cell)


func _build_pickups() -> void:
	for cell: Vector3i in [
		Vector3i(7, 0, 12), Vector3i(25, 0, 19), Vector3i(12, 0, 25), Vector3i(19, 0, 7),
		Vector3i(16, 0, 13), Vector3i(15, 0, 18),
		Vector3i(3, LEDGE_LEVEL, 16), Vector3i(28, LEDGE_LEVEL, 16),
		Vector3i(16, LEDGE_LEVEL, 3), Vector3i(16, LEDGE_LEVEL, 28),
	]:
		_decorate(&"ammo_pickup", cell)
	for cell: Vector3i in _island_origins():
		_decorate(&"ammo_pickup", cell + Vector3i(1, 0, 1))


## Siete, porque las waves autoradas nombran door_01 a door_07 y el loader
## numera las puertas en el orden en que se listan aca.
##
## Van todas sobre el piso exterior, fuera de la huella del anillo: una puerta
## debajo de la pasarela no se ve abrirse, y ver por donde entra la horda es la
## mitad de la informacion que da una wave.
func _build_spawns() -> void:
	_model.set_player_spawn(Vector3i(16, 0, 20))
	var last: int = FLOOR - 1
	var mid: int = int(FLOOR / 2.0)
	for cell: Vector3i in [
		Vector3i(0, 0, mid), Vector3i(last, 0, mid),
		Vector3i(mid, 0, 0), Vector3i(mid, 0, last),
		Vector3i(0, 0, 0), Vector3i(last, 0, last), Vector3i(0, 0, last),
	]:
		_model.add_enemy_spawn(cell)
