class_name ArenaColiseum
extends Node3D
## El venue: un coliseo ovalado generado alrededor de la arena rectangular.
##
## Los otros dos shells repiten un modelo. Este no usa ninguno, y no es por
## ahorrar assets: `tools/measure_stands.gd` mostro que las "gradas" que habia
## eran bloques de 28 triangulos con un reborde a 2m y un paredon a 4m, o sea
## sin una sola superficie donde sentar a nadie. Sembrar publico sobre un modelo
## asi es adivinar donde estan los escalones - y adivinar mal es exactamente lo
## que dejaba a la mitad de la tribuna flotando y a la otra mitad adentro de la
## pared.
##
## Generandolo, el mismo codigo que hace el escalon sabe donde quedo su huella.
## Los asientos no se estiman: salen de `get_seat_rows()`, que devuelve el
## recorrido exacto de cada fila. Es la unica forma de que el publico este
## sentado y no cerca.
##
## Todo el venue es UNA malla. Nada de esto tiene colision: el jugador no puede
## llegar hasta aca -para eso esta el limite de la arena- y un coliseo con
## colision por escalon serian miles de formas que nadie va a tocar nunca.

@export_group("Planta")
## Puntos alrededor del ovalo. Sube el detalle de la curva y el costo, los dos
## de forma lineal.
@export var segments: int = 96
## La forma del ovalo, como exponente de superelipse.
##
## En 2 es una elipse pura. Subiendolo las esquinas se llenan y tiende al
## rectangulo, sin llegar nunca. Es la perilla con la que se afina la planta
## entera sin tocar una linea.
@export_range(2.0, 6.0) var oval_exponent: float = 2.6
## Metros entre el borde de la arena y el arranque de las gradas, medidos en los
## lados. En las esquinas el foso queda mas ancho, y esta bien que quede: es lo
## que hace que la planta se lea como un ovalo y no como un rectangulo con las
## puntas limadas.
@export var pit_margin: float = 8.0

@export_group("Gradas")
## Altura del muro que separa la arena de la primera fila. Es lo que pone al
## publico *sobre* la pelea en vez de al lado.
@export var podium_height: float = 6.0
@export var tiers: int = 3
@export var rows_per_tier: int = 8
## Fondo de cada escalon: donde se sienta la gente.
@export var tread_depth: float = 1.5
## Y cuanto sube cada uno. Los dos juntos son la pendiente; mas alto que hondo
## es una tribuna empinada, que es la del Coliseo y la que deja ver el piso
## desde arriba.
@export var riser_height: float = 1.1
## El pasillo horizontal entre dos anillos de gradas. Es lo que quiebra la
## pendiente y hace que la tribuna se lea como un coliseo y no como un cono.
@export var praecinctio_depth: float = 5.0
## El parapeto al arranque de cada anillo.
@export var parapet_height: float = 1.3

@export_group("Vomitoria")
## Las bocas de tunel que interrumpen las filas. Son lo que mas dice "coliseo"
## por unidad de trabajo: cuestan saltear asientos y un marco oscuro.
@export var vomitoria: int = 12
## Cuanto de la vuelta ocupa cada una.
@export_range(0.0, 0.1) var vomitorium_width: float = 0.022

@export_group("Material")
@export var concrete_color: Color = Color(0.29, 0.30, 0.34)
@export var concrete_roughness: float = 0.9
@export var mouth_color: Color = Color(0.03, 0.035, 0.05)

@export_group("Perimetro")
## El limite de la arena. Sigue siendo cuatro cajas sobre el rectangulo de juego:
## exacto, barato, y es lo que el jugador ya siente hoy. Lo que se ve cambia; lo
## que se choca no.
@export var build_perimeter_walls: bool = true
@export var wall_height: float = 30.0
@export var wall_thickness: float = 2.0
## El piso del foso, entre la arena y el podio. Sin el, ese anillo es un agujero
## al vacio.
@export var build_pit_floor: bool = true

## El publico. Se le pasan las huellas medidas, no una estimacion.
@export var crowd: CrowdStands

var _built: Node3D
var _walls: Node3D
var _seat_rows: Array[Dictionary] = []


func setup(bounds: AABB, _theme: ArenaTheme = null) -> void:
	if _built != null:
		# Sacarlo del arbol antes de liberarlo, no solo encolarlo: `queue_free()`
		# lo deja adentro hasta el fin del frame, y el cuenco nuevo se agrega con
		# el viejo todavia ahi. Godot resuelve ese choque de nombres renombrando
		# al nuevo, y a partir de ahi nadie lo encuentra por el nombre que creia
		# haberle puesto.
		remove_child(_built)
		_built.queue_free()
	_built = Node3D.new()
	_built.name = "Coliseum"
	add_child(_built)

	var centre: Vector3 = bounds.position + bounds.size * 0.5
	var floor_y: float = bounds.position.y
	var axes: Vector2 = _base_axes(bounds)

	_seat_rows = []
	_build_bowl(centre, floor_y, axes)
	if build_pit_floor:
		_build_pit_floor(centre, floor_y, axes)
	if build_perimeter_walls:
		_build_perimeter(bounds)
	if crowd != null:
		crowd.populate_rows(_seat_rows)


# Public API

## El recorrido de cada fila de asientos, de la de mas abajo a la de mas arriba.
## Cada entrada es `{"path": PackedVector3Array}`, que es lo que come
## `CrowdStands.populate_rows()`.
func get_seat_rows() -> Array[Dictionary]:
	return _seat_rows


## Los semiejes del ovalo base, ya agrandados para que el rectangulo de juego
## entre entero.
##
## Se parte de "el borde de la arena mas el foso" en cada eje, y despues se
## escala lo justo para que la esquina del rectangulo quede sobre la curva o
## adentro. Sin ese paso el ovalo corta las esquinas del area de juego, que es
## el unico error de esta forma que el jugador siente en vez de ver.
func _base_axes(bounds: AABB) -> Vector2:
	var half := Vector2(bounds.size.x * 0.5, bounds.size.z * 0.5)
	var wanted := Vector2(half.x + pit_margin, half.y + pit_margin)
	var reach: float = pow(
		pow(half.x / wanted.x, oval_exponent) + pow(half.y / wanted.y, oval_exponent),
		1.0 / oval_exponent)
	return wanted * maxf(reach, 1.0)


# Private

## El cuenco entero, barrido de un perfil.
##
## El perfil es una polilinea 2D -cuanto para afuera, cuanto para arriba- y la
## superficie es esa polilinea girada alrededor del ovalo. Escrito asi, el
## podio, los escalones, los parapetos y los pasillos son todos la misma cosa: un
## tramo del perfil. Nada de eso necesita un caso propio, y agregar un elemento
## nuevo -una galeria arriba, un palco- es agregarle puntos a una lista.
func _build_bowl(centre: Vector3, floor_y: float, axes: Vector2) -> void:
	var profile: Array[Vector2] = []
	## Para cada tramo del perfil: si es una huella donde se sienta gente.
	var is_tread: Array[bool] = []

	profile.push_back(Vector2(0.0, 0.0))
	_step(profile, is_tread, Vector2(0.0, podium_height), false)

	for tier: int in maxi(tiers, 1):
		var top: Vector2 = profile[profile.size() - 1]
		_step(profile, is_tread, top + Vector2(0.0, parapet_height), false)
		for _row: int in maxi(rows_per_tier, 1):
			var at: Vector2 = profile[profile.size() - 1]
			_step(profile, is_tread, at + Vector2(tread_depth, 0.0), true)
			_step(profile, is_tread, profile[profile.size() - 1]
				+ Vector2(0.0, riser_height), false)
		# El ultimo anillo no lleva pasillo detras: no hay nada mas afuera.
		if tier < maxi(tiers, 1) - 1:
			var edge: Vector2 = profile[profile.size() - 1]
			_step(profile, is_tread, edge + Vector2(praecinctio_depth, 0.0), false)

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var previous: PackedVector3Array = _ring(centre, floor_y, axes, profile[0])
	for i: int in profile.size() - 1:
		var current: PackedVector3Array = _ring(centre, floor_y, axes, profile[i + 1])
		_bridge(surface, previous, current)
		if is_tread[i]:
			# El asiento va al medio de la huella, no en su borde.
			_seat_rows.push_back({"path": _ring(centre, floor_y, axes,
				(profile[i] + profile[i + 1]) * 0.5)})
		previous = current

	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "Bowl"
	mesh.mesh = surface.commit()
	mesh.material_override = _concrete()
	_built.add_child(mesh)
	_build_mouths(centre, floor_y, axes, profile)


func _step(profile: Array[Vector2], is_tread: Array[bool], to: Vector2,
		tread: bool) -> void:
	profile.push_back(to)
	is_tread.push_back(tread)


## Un anillo del cuenco a la altura y la distancia que dice `at`.
##
## Correrse hacia afuera es agrandar los dos semiejes por igual, no desplazar la
## curva por su normal. Es aproximado -el ovalo agrandado no es la curva paralela
## exacta- y es lo correcto igual: sale suave, monotona, y garantiza que cada
## fila envuelve a la de adentro, que es lo unico que la tribuna necesita que sea
## cierto.
func _ring(centre: Vector3, floor_y: float, axes: Vector2,
		at: Vector2) -> PackedVector3Array:
	var points := PackedVector3Array()
	var a: float = axes.x + at.x
	var b: float = axes.y + at.x
	var count: int = maxi(segments, 8)
	for i: int in count + 1:
		var angle: float = TAU * float(i) / float(count)
		points.push_back(Vector3(
			centre.x + _superellipse(cos(angle)) * a,
			floor_y + at.y,
			centre.z + _superellipse(sin(angle)) * b))
	return points


## La coordenada de una superelipse a partir de la del circulo.
func _superellipse(value: float) -> float:
	return signf(value) * pow(absf(value), 2.0 / oval_exponent)


func _bridge(surface: SurfaceTool, lower: PackedVector3Array,
		upper: PackedVector3Array) -> void:
	for i: int in mini(lower.size(), upper.size()) - 1:
		surface.add_vertex(lower[i])
		surface.add_vertex(upper[i])
		surface.add_vertex(upper[i + 1])
		surface.add_vertex(lower[i])
		surface.add_vertex(upper[i + 1])
		surface.add_vertex(lower[i + 1])


## Las bocas de tunel, como paneles oscuros contra el parapeto del primer anillo.
##
## Oscuras y no huecas a proposito: un agujero de verdad en la malla se lee como
## un error de modelado, y desde el piso de la arena -que es de donde se mira- un
## panel negro hundido y un tunel real se ven igual.
func _build_mouths(centre: Vector3, floor_y: float, axes: Vector2,
		profile: Array[Vector2]) -> void:
	if vomitoria <= 0 or profile.size() < 3:
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bottom: Vector2 = profile[1]
	var top := Vector2(bottom.x, bottom.y + parapet_height + riser_height * 2.0)

	for index: int in vomitoria:
		var middle: float = float(index) / float(vomitoria)
		var from: float = middle - vomitorium_width * 0.5
		var to: float = middle + vomitorium_width * 0.5
		var lower: PackedVector3Array = _arc(centre, floor_y, axes, bottom, from, to)
		var upper: PackedVector3Array = _arc(centre, floor_y, axes, top, from, to)
		_bridge(surface, lower, upper)

	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "Mouths"
	mesh.mesh = surface.commit()
	mesh.material_override = _unshaded(mouth_color)
	_built.add_child(mesh)


## Un pedazo de anillo, entre dos fracciones de la vuelta.
func _arc(centre: Vector3, floor_y: float, axes: Vector2, at: Vector2,
		from: float, to: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	var a: float = axes.x + at.x
	var b: float = axes.y + at.x
	var steps: int = 6
	for i: int in steps + 1:
		var angle: float = TAU * lerpf(from, to, float(i) / float(steps))
		points.push_back(Vector3(
			centre.x + _superellipse(cos(angle)) * a,
			floor_y + at.y,
			centre.z + _superellipse(sin(angle)) * b))
	return points


## El piso del foso: el ovalo lleno, por debajo del piso de la arena.
##
## Un disco entero y no un anillo, porque a diferencia de un rectangulo dentro de
## otro rectangulo, aca las esquinas del area de juego tocan la curva y un anillo
## dejaria cuatro cunas sin tapar. Va medio metro mas abajo que el piso de las
## piezas, asi que no puede pelearse con ellas por el mismo plano.
func _build_pit_floor(centre: Vector3, floor_y: float, axes: Vector2) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim: PackedVector3Array = _ring(centre, floor_y - 0.5, axes, Vector2.ZERO)
	var middle := Vector3(centre.x, floor_y - 0.5, centre.z)
	for i: int in rim.size() - 1:
		surface.add_vertex(middle)
		surface.add_vertex(rim[i + 1])
		surface.add_vertex(rim[i])
	surface.generate_normals()

	var mesh := MeshInstance3D.new()
	mesh.name = "PitFloor"
	mesh.mesh = surface.commit()
	mesh.material_override = _concrete()
	_built.add_child(mesh)


## Cuatro cajas en el borde del area de juego. Sin malla, y fuera del grupo que
## alimenta el bake de navegacion: paran cuerpos sin ensuciar el navmesh.
##
## Identico a lo que hacen los otros dos shells, a proposito: lo que cambia en
## este venue es lo que se ve, no lo que se choca.
func _build_perimeter(bounds: AABB) -> void:
	if _walls != null:
		remove_child(_walls)
		_walls.queue_free()
	_walls = Node3D.new()
	_walls.name = "Perimeter"
	add_child(_walls)

	var centre: Vector3 = bounds.position + bounds.size * 0.5
	var half := Vector2(bounds.size.x * 0.5, bounds.size.z * 0.5)
	var offsets: Array[Vector3] = [
		Vector3(0.0, 0.0, -half.y - wall_thickness * 0.5),
		Vector3(0.0, 0.0, half.y + wall_thickness * 0.5),
		Vector3(-half.x - wall_thickness * 0.5, 0.0, 0.0),
		Vector3(half.x + wall_thickness * 0.5, 0.0, 0.0),
	]
	var sizes: Array[Vector3] = [
		Vector3(bounds.size.x + wall_thickness * 2.0, wall_height, wall_thickness),
		Vector3(bounds.size.x + wall_thickness * 2.0, wall_height, wall_thickness),
		Vector3(wall_thickness, wall_height, bounds.size.z),
		Vector3(wall_thickness, wall_height, bounds.size.z),
	]
	for index: int in offsets.size():
		var body := StaticBody3D.new()
		body.name = "Wall%d" % index
		var shape := BoxShape3D.new()
		shape.size = sizes[index]
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		body.position = Vector3(centre.x, bounds.position.y + wall_height * 0.5, centre.z) \
			+ offsets[index]
		_walls.add_child(body)


func _concrete() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = concrete_color
	material.roughness = concrete_roughness
	material.metallic = 0.0
	return material


func _unshaded(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
