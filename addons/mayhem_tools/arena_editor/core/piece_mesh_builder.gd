@tool
class_name PieceMeshBuilder
extends RefCounted
## Builds a piece's geometry. A piece with an authored scene gets that scene;
## one without gets a greybox from its footprint, so the catalog is usable long
## before any art exists - and the editor preview and the game show the same box.


static func build(piece: PieceDefinition, catalog: PieceCatalog,
		with_collision: bool = true) -> Node3D:
	if piece == null or catalog == null:
		return null
	if piece.scene != null:
		return piece.scene.instantiate() as Node3D
	return build_greybox(piece, catalog, with_collision)


static func build_greybox(piece: PieceDefinition, catalog: PieceCatalog,
		with_collision: bool) -> Node3D:
	var root: Node3D = StaticBody3D.new() if with_collision else Node3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = piece.greybox_color
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
