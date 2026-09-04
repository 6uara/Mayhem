class_name CrowdStands
extends MultiMeshInstance3D
## El publico en las gradas. Placeholder: son capsulas y se ven como capsulas.
##
## Existe por dos razones a la vez. La primera es que un estadio vacio contradice
## todo lo que el Host viene diciendo - habla todo el tiempo de una multitud que
## no esta. La segunda es que el publico va a dejar de ser decorado: es de estos
## asientos que salen los gadgets que caen a la arena, y `pick_seat()` es la
## puerta por la que el director de drops pregunta desde donde tirar.
##
## Un solo MultiMesh para mil y pico de espectadores, y el idle vive en el
## vertex shader (`crowd_idle.gdshader`). No hay un Node3D por espectador y no
## hay `_process()`: el publico tiene que costar lo mismo con cien que con dos
## mil, porque nadie lo va a mirar de cerca.

const SHADER_PATH: String = "res://assets/shaders/crowd_idle.gdshader"

@export_group("Gradas")
## Filas de asientos, contadas desde el borde del foso hacia afuera.
@export var rows: int = 5
## Metros entre dos espectadores de la misma fila.
@export var seat_spacing: float = 1.35
## Cuanto se aleja cada fila de la arena respecto de la anterior.
@export var row_depth: float = 1.8
## Y cuanto sube. Los dos juntos son la pendiente de la tribuna, y tienen que
## seguir a la del modelo de gradas o el publico flota sobre los escalones.
@export var row_rise: float = 1.1
## Metros entre la primera fila y el borde del foso. El foso ya esta corrido por
## el `pit_margin` del shell; esto es lo que se suma encima.
@export var first_row_offset: float = 1.5
## Fraccion de asientos ocupados. Por debajo de 1 la tribuna tiene huecos, que es
## lo que la hace leerse como gente y no como una textura.
@export_range(0.0, 1.0) var occupancy: float = 0.86

@export_group("Espectador")
@export var seat_height: float = 1.5
@export var seat_radius: float = 0.28
## Desorden lateral y de profundidad, para que las filas no queden a escuadra.
@export var jitter: float = 0.28
## Variacion de altura entre espectadores.
@export var height_jitter: float = 0.18

@export_group("Color")
## Gris apagado a proposito. El ambar es de la casa - dinero, pickups, el Host -
## y un publico ambar compite con las unicas cosas que el jugador tiene que ver.
@export var tint_dark: Color = Tokens.LINE
@export var tint_light: Color = Tokens.DIM

## Posicion de cada asiento en el espacio del nodo, en orden de fila.
##
## Local y no mundial a proposito: `populate()` corre desde el `setup()` del
## shell, y un shell puede estar armandose antes de entrar al arbol - ahi
## `to_global()` no tiene transformada que aplicar y devuelve basura. La
## conversion se hace en `pick_seat()`, que siempre se pregunta en partida.
var _seats: PackedVector3Array = PackedVector3Array()
## Cuantos asientos entraron en las dos primeras filas: los drops salen de ahi.
var _front_seat_count: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(&"crowd")


# Public API

## Siembra la tribuna alrededor de `bounds`, el footprint real de la arena que
## `ArenaRuntime` le pasa al shell. `pit_margin` es el del shell, para que la
## primera fila caiga donde termina el foso y no encima de el.
##
## La semilla sale del tamaño de la arena, no del reloj: la misma arena tiene
## siempre el mismo publico. Una multitud que se reordena en cada carga se nota,
## y se nota como un bug.
func populate(bounds: AABB, pit_margin: float) -> void:
	_seats = PackedVector3Array()
	_front_seat_count = 0
	_rng.seed = hash(Vector3(bounds.size.x, bounds.size.z, float(rows)))

	var centre: Vector3 = bounds.position + bounds.size * 0.5
	var floor_y: float = bounds.position.y
	var base_half := Vector2(
		bounds.size.x * 0.5 + pit_margin + first_row_offset,
		bounds.size.z * 0.5 + pit_margin + first_row_offset)

	var transforms: Array[Transform3D] = []
	var colors: PackedColorArray = PackedColorArray()
	var customs: PackedColorArray = PackedColorArray()

	for row: int in maxi(rows, 0):
		var half: Vector2 = base_half + Vector2.ONE * (row_depth * float(row))
		var y: float = floor_y + row_rise * float(row)
		for seat: Vector2 in _ring_positions(half):
			if _rng.randf() > occupancy:
				continue  # Un asiento vacio. La tribuna llena de punta a punta
				# se lee como una pared, no como gente.
			var scale_y: float = 1.0 + _rng.randfn(0.0, height_jitter)
			var position := Vector3(
				centre.x + seat.x + _rng.randf_range(-jitter, jitter),
				y + seat_height * scale_y * 0.5,
				centre.z + seat.y + _rng.randf_range(-jitter, jitter))
			var basis := Basis()
			basis = basis.scaled(Vector3(1.0, scale_y, 1.0))
			# Mirando a la arena, que es lo unico que el publico vino a ver.
			basis = Basis(Vector3.UP, atan2(-seat.x, -seat.y)) * basis
			transforms.push_back(Transform3D(basis, position))
			colors.push_back(tint_dark.lerp(tint_light, _rng.randf()))
			# x: desfase del bob. y: su ritmo. Ver crowd_idle.gdshader.
			customs.push_back(Color(_rng.randf(), _rng.randf(), 0.0, 0.0))
			_seats.push_back(position)
			if row < 2:
				_front_seat_count += 1

	_build_multimesh(transforms, colors, customs)


## Un asiento al azar de las dos primeras filas, en coordenadas mundiales.
##
## Solo las dos primeras a proposito: es de donde un brazo puede llegar a tirar
## algo a la arena, y es la unica parte de la tribuna que el jugador ve lo
## bastante bien como para que el gadget parezca venir de alguien.
##
## Devuelve `Vector3.ZERO` si la tribuna esta vacia; quien pregunta tiene que
## chequear `has_seats()` antes.
func pick_seat() -> Vector3:
	if _seats.is_empty():
		return Vector3.ZERO
	var pool: int = _front_seat_count if _front_seat_count > 0 else _seats.size()
	return to_global(_seats[_rng.randi() % pool])


func has_seats() -> bool:
	return not _seats.is_empty()


func get_seat_count() -> int:
	return _seats.size()


## Todos los asientos, en el espacio del nodo. La copia que devuelve
## `PackedVector3Array` alcanza para inspeccionar la tribuna sin poder moverla.
##
## El MultiMesh no sirve para esto: en headless el servidor de render es un
## dummy y devuelve transformadas en cero, asi que este array -y no el buffer de
## instancias- es de donde se lee donde quedo sentado cada uno.
func get_seats() -> PackedVector3Array:
	return _seats


# Private

## Las posiciones de una fila, recorriendo el rectangulo de lado `half * 2`.
##
## Rectangulo y no elipse: la arena es un rectangulo y las gradas del shell
## tambien, asi que una fila curva dejaria a los espectadores de las esquinas
## colgando en el aire.
func _ring_positions(half: Vector2) -> Array[Vector2]:
	var found: Array[Vector2] = []
	var spacing: float = maxf(seat_spacing, 0.1)
	var count_x: int = maxi(int(half.x * 2.0 / spacing), 1)
	var count_z: int = maxi(int(half.y * 2.0 / spacing), 1)
	var step_x: float = half.x * 2.0 / float(count_x)
	var step_z: float = half.y * 2.0 / float(count_z)

	for i: int in count_x:
		var x: float = -half.x + step_x * (float(i) + 0.5)
		found.push_back(Vector2(x, -half.y))
		found.push_back(Vector2(x, half.y))
	for i: int in count_z:
		var z: float = -half.y + step_z * (float(i) + 0.5)
		found.push_back(Vector2(-half.x, z))
		found.push_back(Vector2(half.x, z))
	return found


func _build_multimesh(transforms: Array[Transform3D], colors: PackedColorArray,
		customs: PackedColorArray) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = seat_radius
	mesh.height = seat_height
	mesh.radial_segments = 6
	mesh.rings = 2
	mesh.material = _crowd_material()

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i: int in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
		mm.set_instance_custom_data(i, customs[i])
	multimesh = mm
	# El bob mueve los vertices y Godot no lo sabe: sin margen, un espectador en
	# el borde de la caja parpadea cuando el culling decide que ya no esta.
	custom_aabb = mm.get_aabb().grow(1.0)


func _crowd_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(SHADER_PATH)
	return material
