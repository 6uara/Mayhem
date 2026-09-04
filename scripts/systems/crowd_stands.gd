class_name CrowdStands
extends MultiMeshInstance3D
## El publico en las gradas.
##
## Existe por dos razones a la vez. La primera es que un estadio vacio contradice
## todo lo que el Host viene diciendo - habla todo el tiempo de una multitud que
## no esta. La segunda es que el publico no es decorado: es de estos asientos que
## salen los gadgets que caen a la arena, y `pick_seat()` es la puerta por la que
## el director de drops pregunta desde donde tirar.
##
## Un solo MultiMesh de quads y toda la silueta dibujada en el shader
## (`crowd_impostor.gdshader`), sin textura y sin un Node3D por espectador. La
## regla es que la tribuna cueste lo mismo con mil que con diez mil, porque un
## coliseo lleno es mucha gente y ninguno se mira de cerca.
##
## Este nodo no decide nada: siembra asientos y expone las perillas -el
## entusiasmo, la ola, los celulares- para que `CrowdMoodDirector` las mueva. Que
## el publico se levante es una decision sobre el ritmo de la partida, y esas no
## viven en el nodo que dibuja.

const SHADER_PATH: String = "res://assets/shaders/crowd_impostor.gdshader"

@export_group("Gradas")
## Solo se usan cuando nadie le pasa las filas de verdad. El shell tiled se las
## pasa medidas de su propia grada (`populate_rows()`); esto es el respaldo para
## un shell que no sepa hacerlo, y el camino que usan los tests.
@export var fallback_rows: int = 5
@export var fallback_row_depth: float = 1.8
@export var fallback_row_rise: float = 1.1
@export var fallback_first_row_offset: float = 1.5

## Metros entre dos espectadores de la misma fila.
@export var seat_spacing: float = 1.15
## Fraccion de asientos ocupados. Por debajo de 1 la tribuna tiene huecos, que es
## lo que la hace leerse como gente y no como una textura.
@export_range(0.0, 1.0) var occupancy: float = 0.88

@export_group("Espectador")
@export var seat_height: float = 1.75
@export var seat_width: float = 0.9
## Desorden lateral y de profundidad, para que las filas no queden a escuadra.
@export var jitter: float = 0.22
## Variacion de altura entre espectadores.
@export var height_jitter: float = 0.1

@export_group("Color")
## Gris apagado a proposito. El ambar es de la casa - dinero, pickups, el Host -
## y un publico ambar compite con las unicas cosas que el jugador tiene que ver.
@export var tint_dark: Color = Tokens.LINE
@export var tint_light: Color = Tokens.DIM

## Posicion de cada asiento en el espacio del nodo, en orden de fila.
##
## Local y no mundial a proposito: la siembra corre desde el `setup()` del shell,
## y un shell puede estar armandose antes de entrar al arbol - ahi `to_global()`
## no tiene transformada que aplicar y devuelve basura. La conversion se hace en
## `pick_seat()`, que siempre se pregunta en partida.
var _seats: PackedVector3Array = PackedVector3Array()
## Cuantos asientos entraron en las dos primeras filas: los drops salen de ahi.
var _front_seat_count: int = 0
var _rng := RandomNumberGenerator.new()
var _material: ShaderMaterial


func _ready() -> void:
	add_to_group(&"crowd")


# Public API

## Siembra la tribuna sobre filas ya medidas. Cada fila es
## `{"path": PackedVector3Array}`: el recorrido cerrado de la huella donde se
## sienta esa fila, en el espacio del nodo.
##
## Un recorrido y no un rectangulo con una altura, porque el coliseo tiene las
## gradas en ovalo y la tribuna no tiene por que saber que forma tienen. Quien
## genera el escalon sabe exactamente por donde pasa su huella; lo unico que
## hace falta es que lo diga, en vez de que aca se vuelva a deducir.
##
## Este es el camino bueno, y lo usa el shell. La version anterior estimaba las
## alturas con numeros puestos a ojo, y como las "gradas" resultaron ser bloques
## sin rampa, el publico terminaba flotando delante o enterrado adentro.
##
## La semilla sale de la forma de las filas, no del reloj: la misma arena tiene
## siempre el mismo publico. Una multitud que se reordena en cada carga se nota,
## y se nota como un bug.
func populate_rows(rows: Array[Dictionary]) -> void:
	_seats = PackedVector3Array()
	_front_seat_count = 0
	_rng.seed = hash(_seed_of(rows))

	var transforms: Array[Transform3D] = []
	var colors: PackedColorArray = PackedColorArray()
	var customs: PackedColorArray = PackedColorArray()

	for index: int in rows.size():
		for seat: Dictionary in _walk_path(rows[index]["path"]):
			if _rng.randf() > occupancy:
				continue  # Un asiento vacio. La tribuna llena de punta a punta
				# se lee como una pared, no como gente.
			var point: Vector3 = seat["position"]
			var scale_y: float = 1.0 + _rng.randfn(0.0, height_jitter)
			var position := Vector3(
				point.x + _rng.randf_range(-jitter, jitter),
				point.y,
				point.z + _rng.randf_range(-jitter, jitter))
			# El quad se orienta solo hacia la camara, asi que la transformada
			# solo lleva la escala: el shader lee de ella el ancho y el alto, y
			# el origen de la instancia son los pies del espectador.
			var basis := Basis().scaled(
				Vector3(seat_width, seat_height * scale_y, 1.0))
			transforms.push_back(Transform3D(basis, position))
			colors.push_back(tint_dark.lerp(tint_light, _rng.randf()))
			customs.push_back(Color(
				_rng.randf(),          # desfase propio
				_rng.randf(),          # ritmo propio
				_rng.randf(),          # pancarta / celular / nada
				float(seat["ring"])))  # por donde va dando la vuelta, 0..1
			_seats.push_back(position)
			if index < 2:
				_front_seat_count += 1

	_build_multimesh(transforms, colors, customs)


## Siembra la tribuna alrededor de `bounds` inventando las filas.
##
## Respaldo para un shell que no mide sus gradas. `pit_margin` es el del shell,
## para que la primera fila caiga donde termina el foso y no encima de el.
func populate(bounds: AABB, pit_margin: float) -> void:
	var centre: Vector3 = bounds.position + bounds.size * 0.5
	var base_half := Vector2(
		bounds.size.x * 0.5 + pit_margin + fallback_first_row_offset,
		bounds.size.z * 0.5 + pit_margin + fallback_first_row_offset)
	var rows: Array[Dictionary] = []
	for row: int in maxi(fallback_rows, 0):
		var half: Vector2 = base_half + Vector2.ONE * (fallback_row_depth * float(row))
		var y: float = bounds.position.y + fallback_row_rise * float(row)
		rows.push_back({"path": rectangle_path(centre, half, y)})
	populate_rows(rows)


## El recorrido cerrado de un rectangulo, como los que come `populate_rows()`.
##
## Estatico porque lo usan tanto el respaldo de aca como cualquier shell que
## tenga las gradas en rectangulo: la forma de la fila es cosa de quien la
## genera, y esta es la mas simple de todas.
static func rectangle_path(centre: Vector3, half: Vector2, y: float) -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(centre.x - half.x, y, centre.z - half.y),
		Vector3(centre.x + half.x, y, centre.z - half.y),
		Vector3(centre.x + half.x, y, centre.z + half.y),
		Vector3(centre.x - half.x, y, centre.z + half.y),
		Vector3(centre.x - half.x, y, centre.z - half.y),
	])


## Cuanto esta encendida la tribuna, de 0 a 1. Cada espectador tiene su propio
## umbral, asi que subirlo levanta gente de a pedazos y no de golpe.
func set_excitement(value: float) -> void:
	_set_parameter(&"excitement", clampf(value, 0.0, 1.0))


## Donde esta la cresta de la ola dando la vuelta al estadio, de 0 a 1. Fuera de
## ese rango no hay ola, y en -1 se apaga.
func set_wave_position(value: float) -> void:
	_set_parameter(&"wave_position", value)


## Que fraccion de la tribuna tiene el celular prendido.
func set_phone_share(value: float) -> void:
	_set_parameter(&"phone_share", clampf(value, 0.0, 1.0))


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

## Reparte asientos a lo largo de `path`, uno cada `seat_spacing` metros, con el
## parametro 0..1 de cuanto lleva recorrido cada uno.
##
## Ese parametro es lo que hace posible la ola: para que un gesto viaje por la
## tribuna, cada espectador tiene que saber donde esta en la vuelta, y eso no se
## puede reconstruir despues a partir de su posicion sin volver a resolver la
## forma de la fila. Sale gratis aca y no sale gratis en ningun otro lado.
##
## Reparte por longitud de arco y no por vertice: el ovalo del coliseo tiene los
## puntos mas juntos en las puntas, y sembrar uno por vertice amontonaria gente
## ahi y la dejaria rala en los lados largos.
func _walk_path(path: PackedVector3Array) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if path.size() < 2:
		return found

	var lengths := PackedFloat32Array()
	var total: float = 0.0
	for i: int in path.size() - 1:
		total += path[i].distance_to(path[i + 1])
		lengths.push_back(total)
	if total <= 0.0:
		return found

	var count: int = maxi(int(total / maxf(seat_spacing, 0.1)), 4)
	var segment: int = 0
	for i: int in count:
		var travelled: float = (float(i) + 0.5) / float(count) * total
		while segment < lengths.size() - 1 and lengths[segment] < travelled:
			segment += 1
		var from_length: float = lengths[segment - 1] if segment > 0 else 0.0
		var span: float = maxf(lengths[segment] - from_length, 0.0001)
		found.push_back({
			"position": path[segment].lerp(
				path[segment + 1], (travelled - from_length) / span),
			"ring": travelled / total,
		})
	return found


## La semilla del publico: la forma de las filas y nada mas. Dos cargas de la
## misma arena dan las mismas filas, y por lo tanto la misma multitud.
func _seed_of(rows: Array[Dictionary]) -> Vector3:
	if rows.is_empty():
		return Vector3.ZERO
	var first: PackedVector3Array = rows[0]["path"]
	var last: PackedVector3Array = rows[rows.size() - 1]["path"]
	if first.is_empty() or last.is_empty():
		return Vector3(float(rows.size()), 0.0, 0.0)
	return Vector3(first[0].x + last[0].y, first[0].z, float(rows.size()))


func _build_multimesh(transforms: Array[Transform3D], colors: PackedColorArray,
		customs: PackedColorArray) -> void:
	# Un quad de lado 1: el ancho y el alto reales viajan en la escala de cada
	# instancia, y el shader los lee de ahi.
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
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
	# El shader mueve los vertices y Godot no lo sabe: sin margen, un espectador
	# que salta en el borde de la caja parpadea cuando el culling lo descarta.
	custom_aabb = mm.get_aabb().grow(3.0)


func _crowd_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load(SHADER_PATH)
	return _material


func _set_parameter(parameter: StringName, value: Variant) -> void:
	_crowd_material().set_shader_parameter(parameter, value)
