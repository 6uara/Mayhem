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


## `elevated` marca lo que esta por encima del nivel del piso. No es una
## propiedad de la pieza sino de donde se puso: el mismo `floor_3x3` es el suelo
## de la arena en el nivel 0 y una pasarela en el 1, y solo la segunda necesita
## que se le vea el borde.
static func build(piece: PieceDefinition, catalog: PieceCatalog,
		with_collision: bool = true, elevated: bool = false) -> Node3D:
	if piece == null or catalog == null:
		return null
	if piece.scene != null:
		return piece.scene.instantiate() as Node3D
	return build_greybox(piece, catalog, with_collision, elevated)


static func build_greybox(piece: PieceDefinition, catalog: PieceCatalog,
		with_collision: bool, elevated: bool = false) -> Node3D:
	var root: Node3D = StaticBody3D.new() if with_collision else Node3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = piece.greybox_color
	material.roughness = GROUND_ROUGHNESS
	if elevated:
		material.albedo_color = piece.greybox_color.lightened(ELEVATED_LIGHTEN)
		material.roughness = ELEVATED_ROUGHNESS
	var size: Vector3 = catalog.cell_size * piece.greybox_extents
	# Built up from the cell floor, never centred on the cell: a 0.25-high floor
	# tile has to be the ground of its cell, not a slab hanging in the middle of
	# it, or every wall standing on it floats.
	var lift := Vector3(0.0, size.y * 0.5, 0.0)
	for offset: Vector3i in piece.footprint:
		var box := BoxMesh.new()
		box.size = size
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = box
		mesh_instance.material_override = material
		mesh_instance.position = Vector3(offset) * catalog.cell_size + lift
		root.add_child(mesh_instance)
		if not with_collision:
			continue
		var shape := BoxShape3D.new()
		shape.size = size
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = mesh_instance.position
		root.add_child(collision)
	if elevated and piece.edge_energy > 0.0:
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


# Private

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
	var material := StandardMaterial3D.new()
	material.albedo_color = piece.edge_color
	material.emission_enabled = true
	material.emission = piece.edge_color
	material.emission_energy_multiplier = piece.edge_energy
	var bars: Array[Array] = [
		[Vector3(span.x, EDGE_HEIGHT, thickness), Vector3(0.0, 0.0, -span.z * 0.5)],
		[Vector3(span.x, EDGE_HEIGHT, thickness), Vector3(0.0, 0.0, span.z * 0.5)],
		[Vector3(thickness, EDGE_HEIGHT, span.z), Vector3(-span.x * 0.5, 0.0, 0.0)],
		[Vector3(thickness, EDGE_HEIGHT, span.z), Vector3(span.x * 0.5, 0.0, 0.0)],
	]
	for bar: Array in bars:
		var box := BoxMesh.new()
		box.size = bar[0]
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = box
		mesh_instance.material_override = material
		mesh_instance.position = center + (bar[1] as Vector3)
		root.add_child(mesh_instance)
