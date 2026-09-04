class_name EnergyWall
extends Node3D
## El limite de la arena, hecho visible.
##
## Antes era una caja invisible: chocabas con aire, y no habia nada que aprender.
## Este nodo no cambia lo que se choca -la colision sigue siendo las cuatro cajas
## que arma el shell, exactas y baratas- sino lo que se ve al chocarlo.
##
## Lo importante no es que la pared se vea. Es que **conteste**: cuando el
## jugador la toca, una onda se abre desde ese punto. Con eso el limite se
## aprende una vez, en lugar de redescubrirse cada vez que se lo choca de
## costado a media pelea.
##
## El contacto no se detecta con fisica sino midiendo la distancia del jugador a
## cada plano. Rozar una pared corriendo no siempre genera una colision que un
## Area3D reporte, y aca hace falta lo contrario de lo que reporta la fisica: que
## se encienda tambien cuando pasas raspando sin llegar a chocar.

const SHADER_PATH: String = "res://assets/shaders/energy_wall.gdshader"
## Tiene que coincidir con `MAX_IMPACTS` del shader.
const MAX_IMPACTS: int = 8
## Fecha de un hueco sin usar.
##
## Negativa y no cero porque el reloj de la pared arranca en cero: una onda
## registrada en el primer instante de la partida quedaria fechada igual que un
## hueco vacio, y tanto el shader como el conteo la descartarian. Es el primer
## golpe de cada arena, o sea justo el que enseña donde esta el borde.
const EMPTY_IMPACT: float = -1.0

## A que distancia del plano se considera que el jugador lo toco. Mas que cero
## porque el cuerpo tiene radio, y porque una pared que solo se enciende al
## contacto exacto parpadea cuando vas rozandola.
@export var contact_distance: float = 1.6
## Guarda entre dos ondas de la misma pared. Deslizarse a lo largo del borde
## tiene que dejar un rastro de ondas, no una sola ni cien.
@export var contact_cooldown: float = 0.22
## Cuanto sube la pared. Cierra contra el techo: el gancho llega a 28 metros y
## sube con upgrades, y un limite abierto arriba obliga a decidir que pasa
## cuando alguien lo supera - decision que siempre termina en un teletransporte
## o una muerte que el jugador no entiende.
@export var height: float = 30.0

## El reloj propio de la pared.
##
## Las ondas se miden contra esto y no contra el `TIME` del shader: son dos
## relojes distintos -uno lo lleva el motor, el otro arranca cuando se arma la
## arena- y una onda fechada en uno y leida en el otro sale con el radio
## equivocado o directamente no sale.
var _time: float = 0.0
var _impacts: PackedVector4Array = PackedVector4Array()
var _cooldowns: PackedFloat32Array = PackedFloat32Array()
var _next_slot: int = 0
var _planes: Array[Dictionary] = []
var _material: ShaderMaterial
var _player: Node3D


func _ready() -> void:
	_impacts.resize(MAX_IMPACTS)
	_impacts.fill(Vector4(0.0, 0.0, 0.0, EMPTY_IMPACT))
	_cooldowns.resize(4)
	_cooldowns.fill(0.0)


func _process(delta: float) -> void:
	if _planes.is_empty():
		return
	_time += delta
	_material.set_shader_parameter(&"wall_time", _time)

	for i: int in _cooldowns.size():
		_cooldowns[i] = maxf(_cooldowns[i] - delta, 0.0)
	_check_contact()


# Public API

## Levanta la pared sobre el rectangulo del area de juego.
func setup(bounds: AABB) -> void:
	for child: Node in get_children():
		child.queue_free()
	_planes = []

	var centre: Vector3 = bounds.position + bounds.size * 0.5
	var half := Vector2(bounds.size.x * 0.5, bounds.size.z * 0.5)
	var floor_y: float = bounds.position.y
	# Las cuatro caras miran hacia adentro: la normal es lo que decide el
	# fresnel, y una pared con la normal al reves se enciende justo cuando el
	# jugador la mira de frente, que es lo contrario de lo que se quiere.
	_planes = [
		{"normal": Vector3.FORWARD, "middle": Vector3(centre.x, 0.0, centre.z + half.y),
			"span": Vector3(half.x * 2.0, 0.0, 0.0)},
		{"normal": Vector3.BACK, "middle": Vector3(centre.x, 0.0, centre.z - half.y),
			"span": Vector3(half.x * 2.0, 0.0, 0.0)},
		{"normal": Vector3.LEFT, "middle": Vector3(centre.x + half.x, 0.0, centre.z),
			"span": Vector3(0.0, 0.0, half.y * 2.0)},
		{"normal": Vector3.RIGHT, "middle": Vector3(centre.x - half.x, 0.0, centre.z),
			"span": Vector3(0.0, 0.0, half.y * 2.0)},
	]

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for plane: Dictionary in _planes:
		_add_face(surface, plane, floor_y)

	var mesh := MeshInstance3D.new()
	mesh.name = "Field"
	mesh.mesh = surface.commit()
	mesh.material_override = _wall_material()
	# La pared es transparente y aditiva: no proyecta ni recibe sombra, y
	# hacerla proyectar la volveria una caja negra sobre la arena.
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)


## Enciende una onda en `point`. Publica para que cualquier cosa que golpee la
## pared -hoy el jugador, manana un enemigo lanzado contra ella- pueda avisar.
func ripple_at(point: Vector3) -> void:
	if _material == null:
		return
	# Circular: pasado el ultimo hueco se pisa el mas viejo. Ocho ondas a la vez
	# ya es mas de lo que se distingue, y un array que crece seria un array que
	# hay que limpiar.
	_impacts[_next_slot] = Vector4(point.x, point.y, point.z, _time)
	_next_slot = (_next_slot + 1) % MAX_IMPACTS
	_material.set_shader_parameter(&"impacts", _impacts)


func get_impact_count() -> int:
	var live: int = 0
	for impact: Vector4 in _impacts:
		if impact.w > EMPTY_IMPACT:
			live += 1
	return live


# Private

func _add_face(surface: SurfaceTool, plane: Dictionary, floor_y: float) -> void:
	var middle: Vector3 = plane["middle"]
	var span: Vector3 = plane["span"] * 0.5
	var normal: Vector3 = plane["normal"]
	var bottom := Vector3(middle.x, floor_y, middle.z)
	var rise := Vector3(0.0, height, 0.0)
	var corners: Array[Vector3] = [
		bottom - span, bottom + span, bottom + span + rise, bottom - span + rise,
	]
	for index: int in [0, 1, 2, 0, 2, 3]:
		surface.set_normal(normal)
		surface.add_vertex(corners[index])


## El jugador contra los cuatro planos. Se enciende el que esta rozando, no el
## que choco: ver el docstring de la clase.
func _check_contact() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = Players.local()
		if _player == null:
			return
	var position: Vector3 = _player.global_position
	for i: int in _planes.size():
		if _cooldowns[i] > 0.0:
			continue
		var plane: Dictionary = _planes[i]
		var normal: Vector3 = plane["normal"]
		var middle: Vector3 = plane["middle"]
		# Distancia con signo: negativa significa que el jugador esta del lado de
		# afuera, y ahi tampoco hay onda que mostrar.
		var to_plane: float = (position - Vector3(middle.x, position.y, middle.z)).dot(normal)
		if to_plane < 0.0 or to_plane > contact_distance:
			continue
		_cooldowns[i] = contact_cooldown
		ripple_at(position - normal * to_plane)


func _wall_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load(SHADER_PATH)
		_material.set_shader_parameter(&"impacts", _impacts)
	return _material
