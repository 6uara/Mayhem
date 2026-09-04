extends GutTest
## El filete emisivo que hace visibles las plataformas en la arena de noche.
##
## El reporte era "las plataformas no se ven": mismo gris mate, mismo material,
## a una altura de distancia y con el ambiente nocturno del coliseo encima. La
## respuesta no fue subir la luz sino marcar donde termina lo que se pisa.

var _catalog: PieceCatalog


func before_each() -> void:
	_catalog = load("res://data/arena_pieces/default_catalog.tres") as PieceCatalog


func _piece(id: StringName) -> PieceDefinition:
	return _catalog.get_piece(id)


func _emissive_meshes(root: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child: Node in root.get_children():
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null:
			continue
		var material := mesh_instance.material_override as StandardMaterial3D
		if material != null and material.emission_enabled:
			out.append(mesh_instance)
	return out


func test_an_elevated_platform_gets_its_edge_lit() -> void:
	var node: Node3D = PieceMeshBuilder.build(_piece(&"platform_2x2"), _catalog, true, true)
	autofree(node)
	assert_eq(_emissive_meshes(node).size(), 4, "las cuatro barras del perimetro")


## En el nivel del piso no hay borde que marcar: la plataforma *es* el suelo, y
## un filete por celda seria una cuadricula luminosa que nadie pidio.
func test_a_piece_at_ground_level_gets_no_trim() -> void:
	var node: Node3D = PieceMeshBuilder.build(_piece(&"platform_2x2"), _catalog, true, false)
	autofree(node)
	assert_eq(_emissive_meshes(node).size(), 0)


## Que este elevado no alcanza: la pieza tiene que pedirlo desde su `.tres`.
func test_a_piece_without_edge_energy_never_lights_up() -> void:
	var piece: PieceDefinition = _piece(&"platform_2x2").duplicate() as PieceDefinition
	piece.edge_energy = 0.0
	var node: Node3D = PieceMeshBuilder.build(piece, _catalog, true, true)
	autofree(node)
	assert_eq(_emissive_meshes(node).size(), 0)


## Ras con la cubierta a proposito. Un reborde que sobresale lo bakea el navmesh
## como obstaculo y le come el borde util a la plataforma - peor que no verla.
func test_the_trim_lies_flush_with_the_deck() -> void:
	var piece: PieceDefinition = _piece(&"platform_2x2")
	var node: Node3D = PieceMeshBuilder.build(piece, _catalog, true, true)
	autofree(node)
	var top: float = _catalog.cell_size.y * piece.greybox_extents.y
	for mesh_instance: MeshInstance3D in _emissive_meshes(node):
		var box := mesh_instance.mesh as BoxMesh
		var highest: float = mesh_instance.position.y + box.size.y * 0.5
		assert_lt(highest - top, 0.05,
			"el filete no puede ser un escalon sobre la cubierta")


## El filete es decoracion: no agrega ni saca un solo collider.
func test_the_trim_adds_no_collision() -> void:
	var piece: PieceDefinition = _piece(&"platform_2x2")
	var plain: Node3D = PieceMeshBuilder.build(piece, _catalog, true, false)
	autofree(plain)
	var lit: Node3D = PieceMeshBuilder.build(piece, _catalog, true, true)
	autofree(lit)
	assert_eq(_shape_count(lit), _shape_count(plain))


func _shape_count(root: Node3D) -> int:
	var count: int = 0
	for child: Node in root.get_children():
		if child is CollisionShape3D:
			count += 1
	return count


## La otra mitad del arreglo: lo elevado es mas claro y menos rugoso, asi que el
## sol y las luces del coliseo le sacan un reflejo que el piso no tiene.
func test_elevated_ground_reads_brighter_than_the_floor() -> void:
	var piece: PieceDefinition = _piece(&"floor_3x3")
	var ground: Node3D = PieceMeshBuilder.build(piece, _catalog, false, false)
	autofree(ground)
	var raised: Node3D = PieceMeshBuilder.build(piece, _catalog, false, true)
	autofree(raised)
	var ground_material := (ground.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
	var raised_material := (raised.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
	assert_gt(raised_material.albedo_color.v, ground_material.albedo_color.v)
	assert_lt(raised_material.roughness, ground_material.roughness)
