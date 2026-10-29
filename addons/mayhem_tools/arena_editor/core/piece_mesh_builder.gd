@tool
class_name PieceMeshBuilder
extends RefCounted
## Builds a piece's geometry. A piece with an authored scene gets that scene;
## one without gets a greybox from its footprint, so the catalog is usable long
## before any art exists - and the editor preview and the game show the same box.

## Grosor del filete emisivo, en fraccion de celda.
const EDGE_THICKNESS: float = 0.09
## Alto del filete y cuanto se levanta sobre la cara superior. Deliberadamente
## ras: es una franja pintada en el borde de la plataforma, no un escalon. Un
## reborde que sobresalga lo bakea el navmesh como obstaculo y le come el borde
## util a la plataforma, que es peor que no verla.
const EDGE_HEIGHT: float = 0.02
const EDGE_LIFT: float = 0.01
## Cuanto se aclara el albedo de una pieza elevada, y a que rugosidad baja.
##
## La mitad del problema no era falta de luz sino falta de contraste: el mismo
## gris mate a la altura del piso y a una altura de distancia, en una arena de
## noche, es una sola superficie. Una plataforma elevada ahora es mas clara y mas
## brillante, asi que el sol y las luces del coliseo le sacan un reflejo que el
## piso no tiene.
const ELEVATED_LIGHTEN: float = 0.22
const ELEVATED_ROUGHNESS: float = 0.45
const GROUND_ROUGHNESS: float = 0.9
## La chapa de placas de todas las piezas greybox (ver el shader). Lo elevado
## ademas lleva diamante antideslizante: otra senal, aparte del filete, de que
## eso es una pasarela y no el piso.
const SURFACE_SHADER: Shader = preload("res://assets/shaders/arena_surface.gdshader")
const ELEVATED_TREAD: float = 0.8
## Marca de las piezas armadas aca, para que el cargador sepa cuales puede juntar
## en un MultiMesh (ver ArenaGeometryBatcher). Una pieza con escena propia no la
## lleva: su geometria es de quien la modelo.
const GREYBOX_META: StringName = &"greybox"

## Una malla por medida y un material por aspecto, compartidos por todas las
## piezas. Antes cada celda de cada pieza estrenaba su BoxMesh y cada pieza su
## material: unas 1450 mallas y 300 materiales distintos en la arena por defecto,
## y nada que el render pudiera agrupar.
static var _boxes: Dictionary = {}
static var _materials: Dictionary = {}
static var _art_meshes: Dictionary = {}


## `elevated` marca lo que esta por encima del nivel del piso. No es una
## propiedad de la pieza sino de donde se puso: el mismo `floor_3x3` es el suelo
## de la arena en el nivel 0 y una pasarela en el 1, y solo la segunda necesita
## que se le vea el borde.
##
## `cell` es la celda del mundo donde va la pieza: de ahi sale que variante del
## arte lleva cada celda (`art_variants`). Sin ella todas llevan el arte base.
static func build(piece: PieceDefinition, catalog: PieceCatalog,
		with_collision: bool = true, elevated: bool = false, cell: Vector3i = Vector3i.ZERO) -> Node3D:
	if piece == null or catalog == null:
		return null
	if piece.scene != null:
		return piece.scene.instantiate() as Node3D
	return build_greybox(piece, catalog, with_collision, elevated, cell)


static func build_greybox(piece: PieceDefinition, catalog: PieceCatalog,
		with_collision: bool, elevated: bool = false, cell: Vector3i = Vector3i.ZERO) -> Node3D:
	var root: Node3D = StaticBody3D.new() if with_collision else Node3D.new()
	root.set_meta(GREYBOX_META, true)
	var size: Vector3 = catalog.cell_size * piece.greybox_extents
	# Built up from the cell floor, never centred on the cell: a 0.25-high floor
	# tile has to be the ground of its cell, not a slab hanging in the middle of
	# it, or every wall standing on it floats.
	var lift := Vector3(0.0, size.y * 0.5, 0.0)
	var art: Mesh = art_mesh(piece)
	if art != null:
		_add_art(root, piece, catalog, art, with_collision, cell)
	else:
		var material: ShaderMaterial = _surface_material(piece.greybox_color, elevated)
		for offset: Vector3i in piece.footprint:
			var mesh_instance := MeshInstance3D.new()
			mesh_instance.mesh = _box(size)
			mesh_instance.material_override = material
			mesh_instance.position = Vector3(offset) * catalog.cell_size + lift
			root.add_child(mesh_instance)
	var art_collides: bool = art != null and (piece.art_ramp_collision or piece.art_collision)
	if with_collision and not art_collides:
		for offset: Vector3i in piece.footprint:
			var shape := BoxShape3D.new()
			shape.size = size
			var collision := CollisionShape3D.new()
			collision.shape = shape
			collision.position = Vector3(offset) * catalog.cell_size + lift
			root.add_child(collision)
	# La rampa con arte no tiene tapa plana: el filete marcaria el borde de una
	# caja que ya no esta, flotando sobre la pendiente. La suya la trae el modelo.
	var flat_top: bool = not (art != null and piece.art_ramp_collision)
	if elevated and piece.edge_energy > 0.0 and flat_top:
		_add_edge_trim(root, piece, catalog, size.y)
	return root


## The same geometry, unlit and translucent, for the placement ghost.
static func build_preview(piece: PieceDefinition, catalog: PieceCatalog,
		tint: Color) -> Node3D:
	var root: Node3D = build_greybox(piece, catalog, false)
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for child: Node in root.get_children():
		var mesh_instance := child as MeshInstance3D
		if mesh_instance != null:
			mesh_instance.material_override = material
	return root


## La malla del arte de la pieza, o null si no tiene. Una por pieza y compartida,
## igual que las cajas: es lo que deja que ArenaGeometryBatcher junte mil
## baldosas en un MultiMesh.
static func art_mesh(piece: PieceDefinition) -> Mesh:
	return _mesh_of(piece.art_scene)


static func _mesh_of(scene: PackedScene) -> Mesh:
	if scene == null:
		return null
	var key: String = scene.resource_path
	if not _art_meshes.has(key):
		var found: Mesh = null
		var instance: Node = scene.instantiate()
		for node: Node in instance.find_children("*", "MeshInstance3D", true, false):
			found = (node as MeshInstance3D).mesh
			break
		instance.free()
		_art_meshes[key] = found
	return _art_meshes[key]


# Private

## El arte, estirado sobre la caja de cada celda o sobre la del footprint entero.
## Las cajas son las mismas que las de la colision greybox (ver `art_scene`).
static func _add_art(root: Node3D, piece: PieceDefinition, catalog: PieceCatalog,
		art: Mesh, with_collision: bool, world_cell: Vector3i = Vector3i.ZERO) -> void:
	var cell: Vector3 = catalog.cell_size
	var size: Vector3 = cell * piece.greybox_extents
	var boxes: Array[AABB] = []
	if piece.art_bounds.size != Vector3.ZERO:
		boxes.append(piece.art_bounds)
	elif piece.art_per_cell:
		for offset: Vector3i in piece.footprint:
			boxes.append(AABB(Vector3(offset) * cell - Vector3(size.x, 0.0, size.z) * 0.5, size))
	else:
		var lowest: Vector3i = piece.footprint[0]
		var highest: Vector3i = lowest
		for offset: Vector3i in piece.footprint:
			lowest = lowest.min(offset)
			highest = highest.max(offset)
		var start: Vector3 = Vector3(lowest) * cell - Vector3(size.x, 0.0, size.z) * 0.5
		var end: Vector3 = Vector3(highest) * cell + Vector3(size.x * 0.5, size.y, size.z * 0.5)
		boxes.append(AABB(start, end - start))
	var turn := Basis(Vector3.UP, deg_to_rad(piece.art_yaw_degrees))
	# Girado un cuarto de vuelta, el ancho del arte va a lo largo de la caja.
	var quarter: bool = absf(fmod(absf(piece.art_yaw_degrees), 180.0) - 90.0) < 1.0
	var variants: Array[Mesh] = []
	if piece.art_per_cell and piece.art_bounds.size == Vector3.ZERO:
		for scene: PackedScene in piece.art_variants:
			var variant: Mesh = _mesh_of(scene)
			if variant != null:
				variants.append(variant)
	for index: int in boxes.size():
		var box: AABB = boxes[index]
		var local: Vector3 = Vector3(box.size.z, box.size.y, box.size.x) if quarter else box.size
		var mesh: Mesh = art
		var spin := Basis.IDENTITY
		if not variants.is_empty():
			var here: Vector3i = world_cell + piece.footprint[index]
			var picked: int = _variant_for(here, piece.art_variant_chance, variants.size())
			if picked >= 0:
				mesh = variants[picked]
				# Girada un cuarto de vuelta al azar: tres variantes rinden doce.
				spin = Basis(Vector3.UP, PI * 0.5 * float(_cell_hash(here, 7) % 4))
		var place := Transform3D(spin * turn * Basis.from_scale(local),
			box.position + Vector3(box.size.x * 0.5, 0.0, box.size.z * 0.5))
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = mesh
		mesh_instance.transform = place
		root.add_child(mesh_instance)
		# La malla manda sobre la cuña: la rampa choca con todo lo que se ve,
		# barandas y base incluidas. La cuña queda para una rampa sin malla propia.
		if with_collision and piece.art_collision:
			root.add_child(_mesh_collision(mesh, place))
		elif with_collision and piece.art_ramp_collision:
			root.add_child(_ramp_collision(place))


## Que variante lleva esta celda, o -1 para el arte base. Un hash de la celda y
## no randf(): la arena tiene que verse igual cada vez, y en el editor y en el
## juego, y la semilla de la run no tiene nada que ver con el piso.
static func _variant_for(cell: Vector3i, chance: float, count: int) -> int:
	if float(_cell_hash(cell, 1) % 1000) / 1000.0 >= chance:
		return -1
	return _cell_hash(cell, 3) % count


static func _cell_hash(cell: Vector3i, salt: int) -> int:
	return absi(hash(Vector4i(cell.x, cell.y, cell.z, salt)))


## La malla del arte como colision, ya estirada a su caja. Una forma concava: el
## navmesh la lee igual que las cajas, y es la unica que sigue una L.
static func _mesh_collision(art: Mesh, place: Transform3D) -> CollisionShape3D:
	var faces: PackedVector3Array = art.get_faces()
	for index: int in faces.size():
		faces[index] = place * faces[index]
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	return collision


## La cuña de la rampa, en el espacio del arte: sube de y = 0 en +Z a y = 1 en -Z.
static func _ramp_collision(place: Transform3D) -> CollisionShape3D:
	var points := PackedVector3Array()
	for x: float in [-0.5, 0.5]:
		points.append(place * Vector3(x, 0.0, 0.5))
		points.append(place * Vector3(x, 0.0, -0.5))
		points.append(place * Vector3(x, 1.0, -0.5))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var collision := CollisionShape3D.new()
	collision.shape = shape
	return collision


## Cuatro barras finas alrededor del perimetro de la pieza, no de cada celda: un
## `floor_3x3` con filete por celda son treinta y seis mallas para dibujar una
## cuadricula que nadie pidio. Lo que hace falta es donde termina la plataforma.
static func _add_edge_trim(root: Node3D, piece: PieceDefinition,
		catalog: PieceCatalog, top: float) -> void:
	var lowest: Vector3i = piece.footprint[0]
	var highest: Vector3i = lowest
	for offset: Vector3i in piece.footprint:
		lowest = lowest.min(offset)
		highest = highest.max(offset)
	var cell: Vector3 = catalog.cell_size
	var extents: Vector3 = cell * piece.greybox_extents
	var span := Vector3(
		float(highest.x - lowest.x) * cell.x + extents.x, 0.0,
		float(highest.z - lowest.z) * cell.z + extents.z)
	var center := Vector3(
		(float(lowest.x) + float(highest.x)) * 0.5 * cell.x,
		top + EDGE_LIFT,
		(float(lowest.z) + float(highest.z)) * 0.5 * cell.z)
	var thickness: float = minf(cell.x, cell.z) * EDGE_THICKNESS
	var material: StandardMaterial3D = _edge_material(piece.edge_color, piece.edge_energy)
	var bars: Array[Array] = [
		[Vector3(span.x, EDGE_HEIGHT, thickness), Vector3(0.0, 0.0, -span.z * 0.5)],
		[Vector3(span.x, EDGE_HEIGHT, thickness), Vector3(0.0, 0.0, span.z * 0.5)],
		[Vector3(thickness, EDGE_HEIGHT, span.z), Vector3(-span.x * 0.5, 0.0, 0.0)],
		[Vector3(thickness, EDGE_HEIGHT, span.z), Vector3(span.x * 0.5, 0.0, 0.0)],
	]
	for bar: Array in bars:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = _box(bar[0])
		mesh_instance.material_override = material
		mesh_instance.position = center + (bar[1] as Vector3)
		root.add_child(mesh_instance)


static func _box(size: Vector3) -> BoxMesh:
	var key: String = str(size)
	if not _boxes.has(key):
		var box := BoxMesh.new()
		box.size = size
		_boxes[key] = box
	return _boxes[key]


static func _surface_material(color: Color, elevated: bool) -> ShaderMaterial:
	var key: String = "surface|%s|%s" % [color.to_html(), elevated]
	if not _materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = SURFACE_SHADER
		material.set_shader_parameter(&"albedo",
			color.lightened(ELEVATED_LIGHTEN) if elevated else color)
		material.set_shader_parameter(&"roughness",
			ELEVATED_ROUGHNESS if elevated else GROUND_ROUGHNESS)
		material.set_shader_parameter(&"tread_strength", ELEVATED_TREAD if elevated else 0.0)
		_materials[key] = material
	return _materials[key]


static func _edge_material(color: Color, energy: float) -> StandardMaterial3D:
	var key: String = "edge|%s|%s" % [color.to_html(), energy]
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = energy
		_materials[key] = material
	return _materials[key]
