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


## La misma pieza sin arte: lo que se prueba del greybox vale para toda pieza que
## todavia no tiene modelo (paredes, cobertura), aunque el piso ya tenga el suyo.
func _greybox(id: StringName) -> PieceDefinition:
	var piece: PieceDefinition = _piece(id).duplicate() as PieceDefinition
	piece.art_scene = null
	return piece


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
	var piece: PieceDefinition = _greybox(&"floor_3x3")
	var ground: Node3D = PieceMeshBuilder.build(piece, _catalog, false, false)
	autofree(ground)
	var raised: Node3D = PieceMeshBuilder.build(piece, _catalog, false, true)
	autofree(raised)
	var ground_material := (ground.get_child(0) as MeshInstance3D).material_override as ShaderMaterial
	var raised_material := (raised.get_child(0) as MeshInstance3D).material_override as ShaderMaterial
	assert_gt((raised_material.get_shader_parameter(&"albedo") as Color).v,
		(ground_material.get_shader_parameter(&"albedo") as Color).v)
	assert_lt(float(raised_material.get_shader_parameter(&"roughness")),
		float(ground_material.get_shader_parameter(&"roughness")))


## La pasarela lleva chapa antideslizante; el piso del nivel 0 es liso. Es la
## otra senal, ademas del filete, de que eso esta en el aire.
func test_only_elevated_ground_gets_the_tread_plate() -> void:
	var piece: PieceDefinition = _greybox(&"floor_3x3")
	var ground: Node3D = autofree(PieceMeshBuilder.build(piece, _catalog, false, false))
	var raised: Node3D = autofree(PieceMeshBuilder.build(piece, _catalog, false, true))
	var ground_material := (ground.get_child(0) as MeshInstance3D).material_override as ShaderMaterial
	var raised_material := (raised.get_child(0) as MeshInstance3D).material_override as ShaderMaterial
	assert_eq(float(ground_material.get_shader_parameter(&"tread_strength")), 0.0)
	assert_gt(float(raised_material.get_shader_parameter(&"tread_strength")), 0.0)


# ------------------------------------------------------------------ arte

## El piso lleva una baldosa por celda, y es la misma malla en todas las piezas:
## es lo que deja que ArenaGeometryBatcher junte las mil del arena en un MultiMesh.
func test_floor_art_is_one_shared_tile_per_cell() -> void:
	var piece: PieceDefinition = _piece(&"floor_3x3")
	var a: Node3D = autofree(PieceMeshBuilder.build(piece, _catalog, true, false))
	var b: Node3D = autofree(PieceMeshBuilder.build(_piece(&"floor_2x2"), _catalog, true, false))
	var tiles: Array[MeshInstance3D] = []
	for child: Node in a.get_children():
		if child is MeshInstance3D:
			tiles.append(child)
	assert_eq(tiles.size(), piece.footprint.size(), "una baldosa por celda")
	assert_same(tiles[0].mesh, PieceMeshBuilder.art_mesh(piece))
	assert_same((b.get_child(0) as MeshInstance3D).mesh, tiles[0].mesh,
		"floor_2x2 y floor_3x3 comparten la baldosa")


## El arte cambia lo que se ve, nunca lo que se choca: misma cantidad de cajas y
## del mismo tamaño que el greybox, que es de donde sale el navmesh.
func test_art_keeps_the_greybox_collision() -> void:
	var with_art: Node3D = autofree(PieceMeshBuilder.build(_piece(&"floor_3x3"), _catalog, true, false))
	var bare: Node3D = autofree(PieceMeshBuilder.build(_greybox(&"floor_3x3"), _catalog, true, false))
	assert_eq(_shape_count(with_art), _shape_count(bare))
	var art_box := _first_shape(with_art) as BoxShape3D
	var bare_box := _first_shape(bare) as BoxShape3D
	assert_eq(art_box.size, bare_box.size)


## La rampa con arte choca con todo su modelo, barandas y base incluidas: con la
## caja greybox se caminaba en el aire sobre la pendiente, y con una cuña quedaban
## partes del modelo que se veian pero se atravesaban.
func test_the_ramp_collides_as_its_whole_model() -> void:
	var piece: PieceDefinition = _piece(&"ramp_1x1")
	var node: Node3D = autofree(PieceMeshBuilder.build(piece, _catalog, true, false))
	var shape := _first_shape(node) as ConcavePolygonShape3D
	assert_not_null(shape, "la colision es la malla del modelo")
	var tile: MeshInstance3D = null
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			tile = child
	var drawn: AABB = tile.transform * tile.mesh.get_aabb()
	var faces: PackedVector3Array = shape.get_faces()
	var hit := AABB(faces[0], Vector3.ZERO)
	for point: Vector3 in faces:
		hit = hit.expand(point)
	assert_almost_eq(hit.position, drawn.position, Vector3.ONE * 0.05, "empieza donde el modelo")
	assert_almost_eq(hit.end, drawn.end, Vector3.ONE * 0.05, "y termina donde el modelo")


## Sin tapa plana no hay borde que marcar: el filete flotaria sobre la pendiente.
func test_an_elevated_art_ramp_gets_no_trim() -> void:
	var node: Node3D = autofree(PieceMeshBuilder.build(_piece(&"ramp_1x1"), _catalog, true, true))
	assert_eq(_emissive_meshes(node).size(), 0)


func _first_shape(root: Node3D) -> Shape3D:
	for child: Node in root.get_children():
		var collision := child as CollisionShape3D
		if collision != null:
			return collision.shape
	return null


## La esquina choca con su L, no con las tres losas paralelas que armaban sus
## cajas por celda.
func test_the_wall_corner_collides_as_its_model() -> void:
	var node: Node3D = autofree(PieceMeshBuilder.build(_piece(&"wall_corner"), _catalog, true, false))
	assert_eq(_shape_count(node), 1, "una sola forma, la del modelo")
	assert_true(_first_shape(node) is ConcavePolygonShape3D, "sacada de la malla")
	var faces: PackedVector3Array = (_first_shape(node) as ConcavePolygonShape3D).get_faces()
	var hollow: int = 0
	for point: Vector3 in faces:
		if point.x > 1.0 and point.z > 1.0:
			hollow += 1
	assert_eq(hollow, 0, "el cuadrante del hueco de la L queda libre")


## El piso mezcla variantes de la baldosa, y cual va en cada celda sale de la
## celda: la misma arena se arma igual siempre.
func test_floor_variants_are_mixed_in_and_stable() -> void:
	var piece: PieceDefinition = _piece(&"floor_3x3")
	assert_gt(piece.art_variants.size(), 0, "precondicion: el piso trae variantes")
	var base: Mesh = PieceMeshBuilder.art_mesh(piece)
	var variant_tiles: int = 0
	var layout: Array[Mesh] = []
	for x: int in 6:
		for z: int in 6:
			var node: Node3D = autofree(PieceMeshBuilder.build(piece, _catalog, false, false,
				Vector3i(x * 3, 0, z * 3)))
			for child: Node in node.get_children():
				var tile := child as MeshInstance3D
				if tile != null:
					layout.append(tile.mesh)
					if tile.mesh != base:
						variant_tiles += 1
	var share: float = float(variant_tiles) / float(layout.size())
	assert_between(share, 0.15, 0.45, "una parte del piso es variante (%0.2f)" % share)
	var again: Node3D = autofree(PieceMeshBuilder.build(piece, _catalog, false, false, Vector3i.ZERO))
	assert_same((again.get_child(0) as MeshInstance3D).mesh, layout[0], "misma celda, misma baldosa")
	assert_lt(variant_tiles, layout.size(), "y el resto sigue siendo la base")


## El piso se exporta con el mismo metalico que el resto de los props y, con la
## luna y las luces del coliseo, se veia mojado. `art_shine` lo apaga sin tocar el
## .glb, que comparten las piezas que si quieren brillar.
func test_the_floor_art_is_duller_than_the_model_it_comes_from() -> void:
	var piece: PieceDefinition = _piece(&"floor_2x2")
	assert_lt(piece.art_shine, 1.0, "el piso pide menos brillo que el modelo")
	var source: Mesh = null
	var instance: Node = piece.art_scene.instantiate()
	for node: Node in instance.find_children("*", "MeshInstance3D", true, false):
		source = (node as MeshInstance3D).mesh
		break
	instance.free()
	var original := source.surface_get_material(0) as BaseMaterial3D
	var dulled := PieceMeshBuilder.art_mesh(piece).surface_get_material(0) as BaseMaterial3D
	assert_almost_eq(dulled.metallic, original.metallic * piece.art_shine, 0.001)
	assert_almost_eq(dulled.metallic_specular,
		original.metallic_specular * piece.art_shine, 0.001)
	assert_ne(dulled, original, "una copia: el material del .glb queda como estaba")
