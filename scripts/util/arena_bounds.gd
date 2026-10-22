class_name ArenaBounds
extends RefCounted
## La caja jugable de la arena cargada: lo que queda adentro de la pared
## perimetral. La publica ArenaHost al cargar la arena y la limpia al irse.
##
## Existe para poder contestar "este enemigo esta afuera del mapa" sin preguntarle
## al navmesh, que no sirve para eso: el piso se bakea tambien del lado de afuera
## de la pared (ver Enemy.playable_spawn()), asi que estar sobre navmesh no dice
## de que lado se esta. La pared perimetral se levanta exactamente sobre el borde
## de esta caja, asi que un cuerpo que la cruza en el plano esta afuera, sin
## ambiguedad. El reporte del playtest (2026-10-21) fue justamente ese: un enemigo
## del otro lado de la pared, imposible de alcanzar, y la oleada sin poder
## terminar.
##
## Estatica y no un autoload: es un dato, no un sistema, y en los tests sin arena
## simplemente no hay caja y nadie corrige nada.

## Cuanto se puede pasar un cuerpo del borde antes de contar como afuera. La pared
## lo frena antes de eso, asi que pasarse es haber aparecido afuera, no haberse
## apoyado.
const OUTSIDE_TOLERANCE: float = 0.5
## Cuanto por debajo del piso mas bajo cuenta como haberse caido del mapa. La zona
## de muerte de la arena mata antes; esto es para una arena sin ella.
const FALL_DEPTH: float = 25.0

static var _box: AABB = AABB()
static var _has_box: bool = false


static func set_box(box: AABB) -> void:
	_box = box
	_has_box = box.size.x > 0.0 and box.size.z > 0.0


static func clear() -> void:
	_box = AABB()
	_has_box = false


static func has_box() -> bool:
	return _has_box


static func get_box() -> AABB:
	return _box


## Si `point` esta adentro. Sin caja publicada, todo esta adentro: no hay con que
## comparar, y corregir a ciegas seria peor que no corregir.
static func contains(point: Vector3) -> bool:
	if not _has_box:
		return true
	if point.y < _box.position.y - FALL_DEPTH:
		return false
	return point.x >= _box.position.x - OUTSIDE_TOLERANCE \
		and point.x <= _box.end.x + OUTSIDE_TOLERANCE \
		and point.z >= _box.position.z - OUTSIDE_TOLERANCE \
		and point.z <= _box.end.z + OUTSIDE_TOLERANCE


## El punto mas cercano a `point` que queda adentro, a `margin` metros de la pared,
## a la altura del piso. La altura del piso y no la de `point`: lo que estaba afuera
## puede estar en las gradas, a diez metros, o debajo del mapa.
static func clamp_inside(point: Vector3, margin: float) -> Vector3:
	if not _has_box:
		return point
	var inset_x: float = minf(margin, _box.size.x * 0.5)
	var inset_z: float = minf(margin, _box.size.z * 0.5)
	return Vector3(
		clampf(point.x, _box.position.x + inset_x, _box.end.x - inset_x),
		_box.position.y,
		clampf(point.z, _box.position.z + inset_z, _box.end.z - inset_z))
