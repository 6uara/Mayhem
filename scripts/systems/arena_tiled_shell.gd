class_name ArenaTiledShell
extends Node3D
## A venue built by repeating a straight stand and a corner around the arena,
## instead of stretching one bowl to fit it.
##
## This is the answer to the bowl always landing off: a single closed model has
## one knob, scale, and an arena that is not the same shape as its pit comes out
## stretched on one axis and shifted on the other. Sections have no such problem
## - the ring is assembled to the arena's actual size, so it fits exactly at any
## size, and each copy keeps the proportions it was modelled with.
##
## Nothing here reads the models' origins: every piece is placed by its measured
## bounding box, so a section authored around any origin still lands where it
## should.

@export var stand_section: PackedScene
@export var corner_section: PackedScene

@export_group("Fit")
## Metres of floor between the arena and the first row of seats.
@export var pit_margin: float = 4.0
## Sections are repeated a whole number of times and then stretched by whatever
## is left over. Under this much stretch nobody can tell; over it, the shell
## adds another copy instead.
@export var max_section_stretch: float = 1.35
## Uniform scale applied to every copy before it is fitted.
##
## The sections are modelled 4m tall, which around a 72m arena reads as a fence
## rather than a grandstand. This blows them up as a block - depth and height
## together - so the steps keep their proportions; only the length is fitted
## afterwards, and by construction that factor is close to 1.
@export var section_scale: float = 3.0
## Anillos apilados uno sobre otro, cada uno mas afuera y mas arriba que el
## anterior.
##
## Un solo anillo de 12 metros alrededor de una arena de 70 se lee como un
## paredon con escalones, no como un estadio: desde el piso se ve el cielo justo
## arriba del borde. Apilando gradas la tribuna trepa hasta taparlo, que es lo
## que hace que el lugar encierre y que el publico este *sobre* la pelea en vez
## de al lado.
@export var tiers: int = 3
## Cuanto se corre hacia afuera cada anillo, como fraccion de su propia
## profundidad. Por debajo de 1 las gradas se pisan y la tribuna sale mas
## empinada; en 1 la inclinacion es la del modelo repetida.
@export_range(0.3, 1.5) var tier_depth_factor: float = 0.72
## Filas de espectadores sobre la rampa de cada anillo.
@export var rows_per_tier: int = 4
@export var build_apron: bool = true
@export var apron_height: float = 0.75

@export_group("Perimeter")
@export var wall_height: float = 14.0
@export var wall_thickness: float = 2.0
@export var build_perimeter_walls: bool = true

@export_group("Crowd")
## El publico en las gradas. Toma el mismo `pit_margin` con el que se arma el
## anillo, para que la primera fila caiga sobre el primer escalon y no sobre el
## foso.
@export var crowd: CrowdStands

@export_group("Material")
@export var concrete_texture: Texture2D
@export var concrete_tiling: float = 0.25
@export var concrete_color: Color = Color(0.72, 0.72, 0.70)
@export var concrete_roughness: float = 0.92
## Sections come in with balanced normals, so this is off - unlike the bowl.
@export var double_sided: bool = false

var _built: Node3D


## `theme` is accepted for symmetry with `ArenaShell`; a tiled venue takes its
## size from the arena, so there is no pit measurement to read.
func setup(bounds: AABB, _theme: ArenaTheme = null) -> void:
	if _built != null:
		_built.queue_free()
	_built = Node3D.new()
	_built.name = "Ring"
	add_child(_built)

	if stand_section == null or corner_section == null:
		push_error("ArenaTiledShell: needs both a stand and a corner section")
		return

	var stand_size: Vector3 = _measure(stand_section) * section_scale
	var corner_size: Vector3 = _measure(corner_section) * section_scale
	var floor_y: float = bounds.position.y
	var centre: Vector3 = bounds.position + bounds.size * 0.5
	# The ring hugs the arena plus the margin; the corners own the ends of every
	# side and the straight sections fill what is between them.
	var half := Vector2(
		bounds.size.x * 0.5 + pit_margin, bounds.size.z * 0.5 + pit_margin)

	# De adentro hacia afuera: cada anillo apoya sobre el de adentro y se corre
	# hacia atras, que es como se construye una tribuna de verdad.
	for tier: int in maxi(tiers, 1):
		var step: float = stand_size.z * tier_depth_factor * float(tier)
		var tier_half: Vector2 = half + Vector2.ONE * step
		var tier_y: float = floor_y + stand_size.y * float(tier)
		_build_corners(centre, tier_half, corner_size, tier_y, tier)
		_build_sides(centre, tier_half, stand_size, corner_size, tier_y, tier)
	if crowd != null:
		crowd.populate_rows(centre, _seat_rows(half, stand_size, floor_y))
	if build_apron:
		_build_apron(bounds, centre, half, floor_y)
	if build_perimeter_walls:
		_build_perimeter(bounds, centre, floor_y)


## The box the assembled ring occupies. Exists for the tests and for anyone
## debugging a venue that does not line up with its arena.
func get_ring_bounds() -> AABB:
	if _built == null:
		return AABB()
	var bounds := AABB()
	var first: bool = true
	for child: Node in _built.get_children():
		var node := child as Node3D
		if node == null or node.name.begins_with("Apron") or node.name == "Perimeter":
			continue
		var piece: AABB = node.transform * _mesh_bounds(node)
		bounds = piece if first else bounds.merge(piece)
		first = false
	return bounds


# Private

## Las filas de asientos de toda la tribuna, para que quien siembre el publico no
## tenga que adivinar donde estan los escalones.
##
## Es el shell el que sabe esto y nadie mas: las medidas salen de la seccion
## instanciada, asi que cambiar el modelo mueve a la gente con el. La version
## anterior las adivinaba con numeros a ojo, y el publico flotaba delante de la
## grada en vez de estar sentado en ella.
func _seat_rows(half: Vector2, stand_size: Vector3,
		floor_y: float) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var depth_step: float = stand_size.z * tier_depth_factor
	for tier: int in maxi(tiers, 1):
		var tier_half: Vector2 = half + Vector2.ONE * (depth_step * float(tier))
		var tier_y: float = floor_y + stand_size.y * float(tier)
		for row: int in maxi(rows_per_tier, 1):
			# Repartidas parejo sobre la rampa del anillo. La seccion es una
			# grada generica y no dice donde tiene cada escalon; lo que si dice
			# -y es lo que importa- es donde empieza y donde termina la rampa.
			var t: float = (float(row) + 0.5) / float(maxi(rows_per_tier, 1))
			found.push_back({
				"half": tier_half + Vector2.ONE * (depth_step * t),
				"y": tier_y + stand_size.y * t,
			})
	return found


func _build_corners(centre: Vector3, half: Vector2, corner_size: Vector3,
		floor_y: float, tier: int = 0) -> void:
	var corners: Array[Vector2] = [
		Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0),
	]
	for index: int in corners.size():
		var sign_xz: Vector2 = corners[index]
		var target := AABB(
			Vector3(
				centre.x + (half.x if sign_xz.x > 0.0 else -half.x - corner_size.x),
				floor_y,
				centre.z + (half.y if sign_xz.y > 0.0 else -half.y - corner_size.z)),
			Vector3(corner_size.x, corner_size.y, corner_size.z))
		var node: Node3D = corner_section.instantiate() as Node3D
		node.name = "Corner%d_%d" % [tier, index]
		_built.add_child(node)
		# Quarter turns so each copy faces the middle.
		node.rotation.y = deg_to_rad(-90.0 * index)
		_align(node, target)


## The straight runs span the arena's full side; the corners sit outside that
## box, at the ends, so the two meet without a seam and without arithmetic that
## has to agree between them.
func _build_sides(centre: Vector3, half: Vector2, stand_size: Vector3,
		_corner_size: Vector3, floor_y: float, tier: int = 0) -> void:
	# Along X (north and south), then along Z (west and east).
	var runs: Array[Dictionary] = [
		{"axis": "x", "sign": -1.0, "length": half.x * 2.0},
		{"axis": "x", "sign": 1.0, "length": half.x * 2.0},
		{"axis": "z", "sign": -1.0, "length": half.y * 2.0},
		{"axis": "z", "sign": 1.0, "length": half.y * 2.0},
	]
	for index: int in runs.size():
		var run: Dictionary = runs[index]
		var along_x: bool = run["axis"] == "x"
		var span: float = float(run["length"])
		if span <= 0.0:
			continue
		var count: int = maxi(1, int(round(span / stand_size.x)))
		# One more copy rather than a section stretched past recognition.
		while span / (float(count) * stand_size.x) > max_section_stretch:
			count += 1
		var piece_length: float = span / float(count)
		for step: int in count:
			var node: Node3D = stand_section.instantiate() as Node3D
			node.name = "Stand%d_%d_%d" % [tier, index, step]
			_built.add_child(node)
			var target := AABB(Vector3.ZERO, Vector3.ZERO)
			if along_x:
				node.rotation.y = 0.0 if float(run["sign"]) < 0.0 else PI
				var z: float = centre.z - half.y - stand_size.z if float(run["sign"]) < 0.0 \
					else centre.z + half.y
				target = AABB(
					Vector3(centre.x - half.x + piece_length * float(step), floor_y, z),
					Vector3(piece_length, stand_size.y, stand_size.z))
			else:
				node.rotation.y = deg_to_rad(90.0) if float(run["sign"]) < 0.0 \
					else deg_to_rad(-90.0)
				var x: float = centre.x - half.x - stand_size.z if float(run["sign"]) < 0.0 \
					else centre.x + half.x
				target = AABB(
					Vector3(x, floor_y, centre.z - half.y + piece_length * float(step)),
					Vector3(stand_size.z, stand_size.y, piece_length))
			_align(node, target)


## Instances the scene once to measure how big it actually is, origin included.
func _measure(scene: PackedScene) -> Vector3:
	var probe: Node3D = scene.instantiate() as Node3D
	var bounds: AABB = _mesh_bounds(probe)
	probe.free()
	return bounds.size


## Scales and moves `node` so its own bounding box lands exactly on `target`.
##
## Only the length is fitted; depth and height keep what was modelled. Sections
## are long along their local X, and the rotations here are whole quarter turns,
## so which world axis that length lands on has exactly two answers.
func _align(node: Node3D, target: AABB) -> void:
	var local: AABB = _mesh_bounds(node)
	if local.size.x <= 0.0:
		return
	var turned_sideways: bool = absf(sin(node.rotation.y)) > 0.5
	var wanted_length: float = target.size.z if turned_sideways else target.size.x
	node.scale = Vector3(
		wanted_length / local.size.x, section_scale, section_scale)
	# Placed by its bounding box, never by its origin: a section authored around
	# any origin still lands where the ring needs it.
	var placed: AABB = node.transform * local
	node.position += target.position - placed.position
	_paint(node)


## The union of every mesh under `node`, in `node`'s own space - its own
## transform deliberately left out, because the caller is about to apply it.
## Measuring with it folded in was the first version, and it applied every
## rotation twice: sections came out flung across the arena.
func _mesh_bounds(node: Node3D) -> AABB:
	var bounds := AABB()
	var first: bool = true
	var mesh := node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		bounds = mesh.get_aabb()
		first = false
	for child: Node in node.get_children():
		var child_3d := child as Node3D
		if child_3d == null:
			continue
		var child_bounds: AABB = child_3d.transform * _mesh_bounds(child_3d)
		if child_bounds.size == Vector3.ZERO:
			continue
		bounds = child_bounds if first else bounds.merge(child_bounds)
		first = false
	return bounds


func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	var mesh := node as MeshInstance3D
	if mesh != null:
		found.append(mesh)
	for child: Node in node.get_children():
		found.append_array(_find_meshes(child))
	return found


func _paint(node: Node3D) -> void:
	var material: StandardMaterial3D = _concrete_material()
	for mesh: MeshInstance3D in _find_meshes(node):
		mesh.material_override = material


func _concrete_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = concrete_color
	material.albedo_texture = concrete_texture
	material.roughness = concrete_roughness
	material.metallic = 0.0
	# World triplanar: sections are scaled a little to tile exactly, and the slabs
	# have to stay the same size across all of them.
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * concrete_tiling
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if double_sided:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## The floor between the arena and the first row, as a ring of four slabs - never
## a slab under the arena, which would z-fight the player's own floor tiles.
func _build_apron(bounds: AABB, centre: Vector3, half: Vector2, floor_y: float) -> void:
	var material: StandardMaterial3D = _concrete_material()
	var arena_half := Vector2(bounds.size.x * 0.5, bounds.size.z * 0.5)
	var band := Vector2(half.x - arena_half.x, half.y - arena_half.y)
	if band.x <= 0.0 and band.y <= 0.0:
		return
	var sizes: Array[Vector3] = [
		Vector3(half.x * 2.0, apron_height, band.y),
		Vector3(half.x * 2.0, apron_height, band.y),
		Vector3(band.x, apron_height, bounds.size.z),
		Vector3(band.x, apron_height, bounds.size.z),
	]
	var offsets: Array[Vector3] = [
		Vector3(0.0, 0.0, -arena_half.y - band.y * 0.5),
		Vector3(0.0, 0.0, arena_half.y + band.y * 0.5),
		Vector3(-arena_half.x - band.x * 0.5, 0.0, 0.0),
		Vector3(arena_half.x + band.x * 0.5, 0.0, 0.0),
	]
	for index: int in sizes.size():
		if sizes[index].x <= 0.0 or sizes[index].z <= 0.0:
			continue
		var box := BoxMesh.new()
		box.size = sizes[index]
		var slab := MeshInstance3D.new()
		slab.name = "Apron%d" % index
		slab.mesh = box
		slab.material_override = material
		slab.position = Vector3(centre.x, floor_y + apron_height * 0.5, centre.z) \
			+ offsets[index]
		_built.add_child(slab)


func _build_perimeter(bounds: AABB, centre: Vector3, floor_y: float) -> void:
	var half := Vector2(bounds.size.x * 0.5, bounds.size.z * 0.5)
	var sizes: Array[Vector3] = [
		Vector3(bounds.size.x + wall_thickness * 2.0, wall_height, wall_thickness),
		Vector3(bounds.size.x + wall_thickness * 2.0, wall_height, wall_thickness),
		Vector3(wall_thickness, wall_height, bounds.size.z),
		Vector3(wall_thickness, wall_height, bounds.size.z),
	]
	var offsets: Array[Vector3] = [
		Vector3(0.0, 0.0, -half.y - wall_thickness * 0.5),
		Vector3(0.0, 0.0, half.y + wall_thickness * 0.5),
		Vector3(-half.x - wall_thickness * 0.5, 0.0, 0.0),
		Vector3(half.x + wall_thickness * 0.5, 0.0, 0.0),
	]
	var walls := Node3D.new()
	walls.name = "Perimeter"
	_built.add_child(walls)
	for index: int in sizes.size():
		var body := StaticBody3D.new()
		body.name = "Wall%d" % index
		var shape := BoxShape3D.new()
		shape.size = sizes[index]
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		body.position = Vector3(centre.x, floor_y + wall_height * 0.5, centre.z) + offsets[index]
		walls.add_child(body)
