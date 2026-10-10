@tool
class_name ArenaGeometryBatcher
extends RefCounted
## Junta la geometria greybox de una arena cargada en un MultiMesh por malla y
## material.
##
## La arena por defecto son ~300 piezas y ~1450 cajas: armada pieza por pieza,
## cada caja era un draw call, y otro mas por cascada de sombra. Medido en una
## GPU integrada (Radeon 680M) eran mas de 3000 draw calls en un frame sin un
## solo enemigo. Con mallas y materiales ya compartidos (PieceMeshBuilder), lo
## que queda es dibujarlas juntas.
##
## Solo toca lo que se dibuja. Cada pieza sigue siendo su propio nodo, con su
## nombre y su colision - el navmesh se bakea de los colliders, los tests y el
## editor buscan piezas por nombre - y lo unico que pierde son sus
## MeshInstance3D, que pasan a ser una instancia de un MultiMesh. Una pieza con
## escena propia (las que tienen arte) no se toca.

const ROOT_NAME: String = "BatchedGeometry"


## Junta lo de `geometry_root` en multimeshes nuevos bajo `owner`. Devuelve
## cuantas mallas sueltas reemplazo.
static func batch(owner: Node3D, geometry_root: Node3D) -> int:
	var groups: Dictionary = {}  # "mesh_id|material_id" -> {mesh, material, transforms}
	var replaced: int = 0
	var to_root: Transform3D = geometry_root.transform
	for piece_node: Node in geometry_root.get_children():
		var piece := piece_node as Node3D
		if piece == null or not piece.has_meta(PieceMeshBuilder.GREYBOX_META):
			continue
		for child: Node in piece.get_children():
			var mesh_instance := child as MeshInstance3D
			if mesh_instance == null or mesh_instance.mesh == null:
				continue
			var material: Material = mesh_instance.material_override
			var key: String = "%d|%d" % [mesh_instance.mesh.get_instance_id(),
				material.get_instance_id() if material != null else 0]
			if not groups.has(key):
				groups[key] = {"mesh": mesh_instance.mesh, "material": material,
					"transforms": []}
			(groups[key]["transforms"] as Array).append(
				to_root * piece.transform * mesh_instance.transform)
			piece.remove_child(mesh_instance)
			mesh_instance.queue_free()
			replaced += 1
	if groups.is_empty():
		return 0

	var root := Node3D.new()
	root.name = ROOT_NAME
	owner.add_child(root)
	for key: String in groups:
		var group: Dictionary = groups[key]
		var transforms: Array = group["transforms"]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = group["mesh"]
		multimesh.instance_count = transforms.size()
		for index: int in transforms.size():
			multimesh.set_instance_transform(index, transforms[index])
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.material_override = group["material"]
		root.add_child(instance)
	return replaced
