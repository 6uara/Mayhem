@tool
extends SceneTree
## Lo comun a los scripts que construyen las arenas que vienen con el juego.
## Cada arena es un script que extiende este y completa `_build()`; correrlo
## headless escribe su `.tres`:
##   godot --headless --path . -s tools/make_<arena>_arena.gd
##
## `make_default_arena.gd` (The Pit) es anterior y no pasa por aca: su `.tres` se
## corrigio a mano despues de generarlo (los pads, en b33ba05), y regenerarlo
## desde el script desharia eso.

const CATALOG_PATH: String = "res://data/arena_pieces/default_catalog.tres"
## El unico tamano que hay. 32x32 celdas de 4m: un piso de 128m.
const GRID: Vector3i = ArenaData.FIXED_SIZE
## Lo que ocupa el piso, que es la grilla entera: el coliseo se arma al tamano
## del contenido y los regalos del publico caen al nivel 0, asi que ninguna
## arena del juego deja vacio en el piso.
const FLOOR: int = 32

var arena: ArenaData
var _model: PlacementModel
var _failures: int = 0
var _skipped: int = 0


func _initialize() -> void:
	var catalog := load(CATALOG_PATH) as PieceCatalog
	if catalog == null:
		push_error("%s: no catalog at %s" % [_out_path(), CATALOG_PATH])
		quit(1)
		return

	arena = ArenaData.new()
	arena.arena_name = _arena_name()
	arena.grid_size = GRID
	arena.theme_id = &"coliseum"
	arena.author = "mayhem"
	arena.created_at = Time.get_datetime_string_from_system(true)
	_model = PlacementModel.new(arena, catalog)

	_build()

	if _failures > 0:
		push_error("%d placements were refused; the arena is not what this script says" % _failures)
		quit(1)
		return

	var issues: Array[ValidationIssue] = ArenaValidator.validate(arena, catalog)
	for issue: ValidationIssue in issues:
		print("%s %s: %s" % [
			"ERROR " if issue.is_error() else "WARN  ", issue.code, issue.message])
	if not ArenaValidator.errors(issues).is_empty():
		push_error("%s: the arena does not validate" % _out_path())
		quit(1)
		return

	var graph: GridGraph = GridGraph.build(arena, catalog)
	print("%s | pieces: %d | skipped decor: %d | walkable: %d | enemy spawns: %d | nav links: %d" % [
		arena.arena_name, arena.placements.size(), _skipped, graph.walkable_cells().size(),
		arena.enemy_spawns.size(), graph.shared_links().size()])
	var error: Error = ArenaIO.save(arena, _out_path())
	print("saved %s (%d)" % [_out_path(), error])
	quit(0 if error == OK else 1)


# Lo que completa cada arena

func _arena_name() -> String:
	return ""


func _out_path() -> String:
	return ""


func _build() -> void:
	pass


# Ayudas

## Placing through here rather than `model.place` directly: a refusal used to be
## a silently missing piece, and an arena that quietly lost its anchors still
## saved and still validated. Now the build fails and says which cell.
func _place(piece_id: StringName, cell: Vector3i, rotation: int = 0) -> void:
	var refusal: StringName = _model.refusal_for(piece_id, cell, rotation)
	if refusal != &"":
		push_error("%s at %s refused: %s" % [piece_id, cell, refusal])
		_failures += 1


## Para la decoracion que se reparte por formula. Que caiga sobre algo ya puesto
## es el precio de repartirla con un `for`: se saltea y se cuenta. Cualquier otro
## rechazo sigue siendo un error.
func _decorate(piece_id: StringName, cell: Vector3i, rotation: int = 0) -> void:
	var refusal: StringName = _model.refusal_for(piece_id, cell, rotation)
	if refusal == &"":
		return
	if refusal == &"cell_taken":
		_skipped += 1
		return
	push_error("%s at %s refused: %s" % [piece_id, cell, refusal])
	_failures += 1


## Un rectangulo de piso en `level`, con baldosas de 3x3 donde entran y de 2x2 o
## 1x1 en el sobrante: el piso entero en `floor_1x1` serian mil StaticBody.
## `largest` baja la baldosa mas grande para las franjas de ancho par, que con
## 3x3 dejan una fila entera de 1x1.
func _fill_floor(level: int, from: Vector2i, size: Vector2i, largest: int = 3) -> void:
	var taken: Dictionary = {}
	for x: int in range(from.x, from.x + size.x):
		for z: int in range(from.y, from.y + size.y):
			if taken.has(Vector2i(x, z)):
				continue
			for tile: int in [3, 2, 1]:
				if tile > largest or not _tile_fits(Vector2i(x, z), tile, from, size, taken):
					continue
				for dx: int in tile:
					for dz: int in tile:
						taken[Vector2i(x + dx, z + dz)] = true
				_place(StringName("floor_%dx%d" % [tile, tile]), Vector3i(x, level, z))
				break


## Una franja de muro de `from` a `to` (inclusive) sobre una linea, sin las
## celdas de `gaps`. `along_z` elige el eje: un `wall_2x1` sin girar corre en +X
## y con un cuarto de vuelta en +Z. Los tramos impares cierran con un `wall_1x1`.
func _wall_run(fixed: int, from: int, to: int, along_z: bool, gaps: Array[int]) -> void:
	var rotation: int = 1 if along_z else 0
	var i: int = from
	while i <= to:
		if gaps.has(i):
			i += 1
			continue
		var cell := Vector3i(fixed, 0, i) if along_z else Vector3i(i, 0, fixed)
		if i + 1 <= to and not gaps.has(i + 1):
			_place(&"wall_2x1", cell, rotation)
			i += 2
		else:
			_place(&"wall_1x1", cell, rotation)
			i += 1


func _tile_fits(origin: Vector2i, tile: int, from: Vector2i, size: Vector2i,
		taken: Dictionary) -> bool:
	if origin.x + tile > from.x + size.x or origin.y + tile > from.y + size.y:
		return false
	for dx: int in tile:
		for dz: int in tile:
			if taken.has(Vector2i(origin.x + dx, origin.y + dz)):
				return false
	return true
