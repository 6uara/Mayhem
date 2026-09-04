class_name ArenaRoof
extends Node3D
## El techo del estadio: anillo estructural, vigas, y un oculo abierto al cielo.
##
## Existe por una razon de juego antes que de imagen. El gancho llega a 28 metros
## y sube con upgrades, y ademas hay dash, bounce pads y zip lines: un limite
## abierto arriba obliga a decidir que pasa cuando alguien lo supera, y esa
## decision siempre termina siendo un teletransporte o una muerte que el jugador
## no entiende. Cerrando, no hay ningun caso raro que explicar.
##
## Que cierre no quiere decir que tape. El oculo del medio deja ver el cielo y es
## por donde bajan los haces de luz, asi que el techo da el encierro sin cobrar
## la noche que se acaba de construir.
##
## La colision es UNA caja plana sobre el area de juego. Igual que con la pared:
## lo que se ve puede ser todo lo complicado que haga falta, lo que se choca no.

@export_group("Forma")
## Cuanto del ancho del techo queda abierto. En 0 el estadio es una lata.
@export_range(0.05, 0.9) var oculus_share: float = 0.42
## Cuanto sube el techo por encima del ultimo escalon de la tribuna.
@export var rise_above_rim: float = 10.0
## Cuanto se hunde el borde del oculo respecto del anillo exterior, para que el
## techo sea un embudo y no una tapa plana.
@export var oculus_drop: float = 6.0
@export var segments: int = 96
@export var thickness: float = 1.6

@export_group("Vigas")
## Vigas radiales desde el anillo exterior hasta el borde del oculo.
@export var trusses: int = 24
@export var truss_width: float = 1.2

@export_group("Haces")
## Columnas de luz que bajan por el oculo hasta el piso de la arena. Son conos
## con material aditivo, no luces: una SpotLight3D con sombras por cada haz
## costaria mas que todo el resto del venue junto.
@export var beams: int = 6
@export var beam_top_radius: float = 2.2
@export var beam_bottom_radius: float = 9.0
@export var beam_color: Color = Color(0.55, 0.86, 1.0)
@export_range(0.0, 1.0) var beam_opacity: float = 0.06

@export_group("Material")
@export var structure_color: Color = Color(0.10, 0.11, 0.15)
@export var truss_color: Color = Color(0.16, 0.18, 0.24)

@export_group("Colision")
## El techo para al jugador. Sin esto todo lo anterior es decorado y el limite
## sigue abierto por arriba.
@export var build_ceiling_collision: bool = true

var _built: Node3D
var _ceiling: StaticBody3D
var _height: float = 0.0


## Arma el techo sobre una tribuna que llega hasta `reach` de ancho y
## `rim_height` de alto. `bounds` es el area de juego, que es lo que el techo
## tiene que tapar con colision.
func setup(bounds: AABB, reach: Vector2, rim_height: float) -> void:
	if _built != null:
		remove_child(_built)
		_built.queue_free()
	_built = Node3D.new()
	_built.name = "Roof"
	add_child(_built)

	var centre: Vector3 = bounds.position + bounds.size * 0.5
	_height = rim_height + rise_above_rim

	_build_canopy(centre, reach)
	_build_trusses(centre, reach)
	_build_beams(centre, bounds)
	if build_ceiling_collision:
		_build_ceiling(bounds)


# Public API

## La altura del anillo exterior del techo, que es el punto mas alto del venue.
func get_height() -> float:
	return _height


## El semieje del hueco abierto en el medio.
func get_oculus_reach(reach: Vector2) -> Vector2:
	return reach * oculus_share


# Private

## El faldon: un embudo entre el anillo exterior y el borde del oculo.
##
## Dos superficies -la de abajo, que es la que se ve desde la arena, y la de
## arriba- unidas por el canto. Sin la de arriba, mirar por el oculo desde
## adentro deja ver el techo por detras y el estadio se lee hueco.
func _build_canopy(centre: Vector3, reach: Vector2) -> void:
	var outer: Vector2 = reach
	var inner: Vector2 = get_oculus_reach(reach)
	var outer_y: float = _height
	var inner_y: float = _height - oculus_drop

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for level: float in [0.0, thickness]:
		var rim: PackedVector3Array = _ring(centre, outer, outer_y + level)
		var lip: PackedVector3Array = _ring(centre, inner, inner_y + level)
		# La cara de abajo se cose al reves que la de arriba, o una de las dos
		# queda con las normales para el lado contrario y se ve negra.
		if is_zero_approx(level):
			_bridge(surface, lip, rim)
		else:
			_bridge(surface, rim, lip)
	# El canto del oculo, que es lo que le da espesor al agujero visto de abajo.
	_bridge(surface,
		_ring(centre, inner, inner_y),
		_ring(centre, inner, inner_y + thickness))

	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "Canopy"
	mesh.mesh = surface.commit()
	mesh.material_override = _solid(structure_color)
	_built.add_child(mesh)


## Las vigas radiales, por debajo del faldon. Es lo que dice que esto es una
## estructura y no una tapa.
func _build_trusses(centre: Vector3, reach: Vector2) -> void:
	if trusses <= 0:
		return
	var inner: Vector2 = get_oculus_reach(reach)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	for index: int in trusses:
		var angle: float = TAU * float(index) / float(trusses)
		var direction := Vector2(cos(angle), sin(angle))
		var from := Vector3(
			centre.x + direction.x * inner.x, _height - oculus_drop - thickness * 0.5,
			centre.z + direction.y * inner.y)
		var to := Vector3(
			centre.x + direction.x * reach.x, _height - thickness * 0.5,
			centre.z + direction.y * reach.y)
		_add_beam(surface, from, to, truss_width)

	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "Trusses"
	mesh.mesh = surface.commit()
	mesh.material_override = _solid(truss_color)
	_built.add_child(mesh)


## Los haces que bajan por el oculo. Conos aditivos: se ven contra el cielo
## oscuro y no cuestan una sola sombra.
func _build_beams(centre: Vector3, bounds: AABB) -> void:
	if beams <= 0:
		return
	var container := Node3D.new()
	container.name = "Beams"
	_built.add_child(container)

	var floor_y: float = bounds.position.y
	var spread: float = minf(bounds.size.x, bounds.size.z) * 0.3
	var material := _additive(beam_color, beam_opacity)
	for index: int in beams:
		var angle: float = TAU * float(index) / float(beams)
		var cone := CylinderMesh.new()
		cone.top_radius = beam_top_radius
		cone.bottom_radius = beam_bottom_radius
		cone.height = _height - oculus_drop - floor_y
		cone.radial_segments = 12
		cone.rings = 1
		cone.material = material

		var mesh := MeshInstance3D.new()
		mesh.name = "Beam%d" % index
		mesh.mesh = cone
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.position = Vector3(
			centre.x + cos(angle) * spread,
			floor_y + cone.height * 0.5,
			centre.z + sin(angle) * spread)
		container.add_child(mesh)


## La tapa que para al jugador: una sola caja plana sobre el area de juego.
func _build_ceiling(bounds: AABB) -> void:
	if _ceiling != null:
		remove_child(_ceiling)
		_ceiling.queue_free()
	_ceiling = StaticBody3D.new()
	_ceiling.name = "Ceiling"
	var shape := BoxShape3D.new()
	# Mas ancha que la arena: si terminara justo en el borde, el jugador podria
	# meterse por la junta entre el techo y la pared.
	shape.size = Vector3(bounds.size.x * 1.4, 2.0, bounds.size.z * 1.4)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	_ceiling.add_child(collision)
	var centre: Vector3 = bounds.position + bounds.size * 0.5
	_ceiling.position = Vector3(centre.x, _height - oculus_drop, centre.z)
	add_child(_ceiling)


func _ring(centre: Vector3, axes: Vector2, y: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	var count: int = maxi(segments, 8)
	for i: int in count + 1:
		var angle: float = TAU * float(i) / float(count)
		points.push_back(Vector3(
			centre.x + cos(angle) * axes.x, y, centre.z + sin(angle) * axes.y))
	return points


func _bridge(surface: SurfaceTool, lower: PackedVector3Array,
		upper: PackedVector3Array) -> void:
	for i: int in mini(lower.size(), upper.size()) - 1:
		surface.add_vertex(lower[i])
		surface.add_vertex(upper[i])
		surface.add_vertex(upper[i + 1])
		surface.add_vertex(lower[i])
		surface.add_vertex(upper[i + 1])
		surface.add_vertex(lower[i + 1])


## Una viga como caja entre dos puntos.
func _add_beam(surface: SurfaceTool, from: Vector3, to: Vector3, width: float) -> void:
	var along: Vector3 = (to - from)
	if along.length_squared() <= 0.0001:
		return
	var forward: Vector3 = along.normalized()
	var side: Vector3 = forward.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized() * width * 0.5
	var up: Vector3 = side.cross(forward).normalized() * width * 0.5

	var corners: Array[Vector3] = [
		from - side - up, from + side - up, from + side + up, from - side + up,
		to - side - up, to + side - up, to + side + up, to - side + up,
	]
	var faces: Array = [
		[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7],
	]
	for face: Array in faces:
		for index: int in [0, 1, 2, 0, 2, 3]:
			surface.add_vertex(corners[face[index]])


func _solid(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	material.metallic = 0.2
	return material


func _additive(color: Color, opacity: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	# Sin escribir profundidad: los haces se cruzan entre si y con la pared de
	# energia, y cualquiera de los dos escribiendo profundidad recorta al otro.
	material.no_depth_test = false
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.albedo_color = Color(color.r, color.g, color.b, opacity)
	return material
