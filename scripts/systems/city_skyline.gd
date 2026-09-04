class_name CitySkyline
extends MultiMeshInstance3D
## La ciudad detras del coliseo.
##
## Existe para contestar una pregunta que el venue deja abierta apenas se hace de
## noche: donde pasa esto. Un coliseo solo contra un cielo negro es una ruina; el
## mismo coliseo con torres encendidas detras es un espectaculo que alguien esta
## transmitiendo desde algun lado.
##
## Cajas de verdad, no siluetas planas. Un anillo de billboards gira con la
## camara, y en un juego donde el jugador corre, dashea y se cuelga de un gancho,
## ese giro se nota en cada desplazamiento. Doce triangulos por torre y un solo
## MultiMesh: la ciudad entera es una draw call.
##
## Las ventanas no son geometria ni textura: las dibuja `city_block.gdshader`
## sobre la fachada, en metros, para que una torre ancha no tenga ventanas
## anchas.

const SHADER_PATH: String = "res://assets/shaders/city_block.gdshader"

@export_group("Anillo")
## Metros entre el borde de las gradas y la primera torre. Grande a proposito:
## la ciudad tiene que leerse lejos, o el coliseo parece estar en una plaza.
@export var stand_off: float = 90.0
## Cuantos anillos de torres, uno detras del otro. Dos o tres alcanzan para que
## haya profundidad sin que nada de esto se vea de cerca.
@export var depth_rings: int = 3
@export var ring_spacing: float = 55.0
## Torres por anillo.
@export var towers_per_ring: int = 44

@export_group("Torres")
@export var min_height: float = 30.0
@export var max_height: float = 150.0
@export var min_width: float = 14.0
@export var max_width: float = 34.0
## Cuanto se corre cada torre de su lugar en el anillo, para que la fila no se
## lea como una fila.
@export var jitter: float = 22.0
## Fraccion de ventanas encendidas, de la torre mas apagada a la mas despierta.
@export var lit_share: Vector2 = Vector2(0.12, 0.42)
## Cuantas torres tienen ventanas calidas en vez de frias.
@export_range(0.0, 1.0) var warm_share: float = 0.35

var _rng := RandomNumberGenerator.new()
var _material: ShaderMaterial
## Donde quedo cada torre.
##
## El MultiMesh no sirve para leer esto de vuelta: en headless el servidor de
## render es un dummy que acepta las transformadas y despues las devuelve todas
## en cero. Es el mismo motivo por el que `CrowdStands` guarda sus asientos.
var _towers: Array[Transform3D] = []


## Siembra la ciudad alrededor de `centre`, por fuera de `reach` -que es hasta
## donde llegan las gradas- y con la base a la altura `floor_y`.
##
## Las torres arrancan hundidas por debajo del piso de la arena: nunca se ve su
## base, siempre esta tapada por el borde superior de la tribuna, y hundirlas
## evita tener que decidir a que altura esta el suelo de una ciudad que no
## existe.
func populate(centre: Vector3, reach: Vector2, floor_y: float) -> void:
	_rng.seed = hash(Vector3(centre.x, centre.z, reach.x))

	var transforms: Array[Transform3D] = []
	_towers = transforms
	var customs: PackedColorArray = PackedColorArray()

	for ring: int in maxi(depth_rings, 1):
		var radius: Vector2 = reach + Vector2.ONE * (
			stand_off + ring_spacing * float(ring))
		for index: int in maxi(towers_per_ring, 1):
			var angle: float = TAU * (float(index) + _rng.randf() * 0.6) \
				/ float(maxi(towers_per_ring, 1))
			var height: float = _rng.randf_range(min_height, max_height)
			# Las de atras son mas altas, o el anillo de adelante las tapa
			# enteras y los anillos de atras no aportan nada.
			height *= 1.0 + 0.45 * float(ring)
			var width: float = _rng.randf_range(min_width, max_width)
			var depth: float = _rng.randf_range(min_width, max_width)

			var position := Vector3(
				centre.x + cos(angle) * radius.x + _rng.randf_range(-jitter, jitter),
				floor_y - height * 0.5,
				centre.z + sin(angle) * radius.y + _rng.randf_range(-jitter, jitter))
			var basis := Basis().scaled(Vector3(width, height, depth))
			# La caja viene centrada en su origen, asi que el centro va a media
			# altura por encima de la base hundida.
			position.y += height * 0.5
			transforms.push_back(Transform3D(basis, position))
			customs.push_back(Color(
				_rng.randf(),
				_rng.randf_range(lit_share.x, lit_share.y),
				1.0 if _rng.randf() < warm_share else 0.0,
				0.0))

	_build(transforms, customs)


func get_tower_count() -> int:
	return _towers.size()


## Donde quedo cada torre. Ver `_towers`.
func get_towers() -> Array[Transform3D]:
	return _towers


# Private

func _build(transforms: Array[Transform3D], customs: PackedColorArray) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	mesh.material = _tower_material()

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i: int in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_custom_data(i, customs[i])
	multimesh = mm


func _tower_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load(SHADER_PATH)
	return _material
