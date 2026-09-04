class_name ArenaShell
extends Node3D
## The venue around an authored arena: the stands bowl, the perimeter wall, and
## the concrete they are made of.
##
## `ArenaRuntime` hands this `setup(bounds)` with the arena's real footprint, so
## one shell serves the three grid presets instead of one scene per size. The
## stands are stretched to fit rather than tiled: the model is a single closed
## bowl, and the only knob a single mesh gives you is scale.

## The hole in the middle of the stands model, in its own units, measured off
## the mesh with `tools/measure_shell_pit.gd`. The theme carries the same two
## numbers and wins when it has them, so the editor and the runtime always agree
## on the venue's shape; these stay as the fallback for a shell used on its own.
@export var pit_size: Vector2 = Vector2(19.0, 9.5)
@export var pit_center: Vector2 = Vector2(0.0, -4.75)

@export_group("Fit")
## Metres of pit floor left around the arena, so the play area never touches the
## first tier of seats.
@export var pit_margin: float = 2.0
## Vertical scale of the stands, kept off the horizontal fit on purpose:
## stretching a 64m arena to 128m should widen the terraces, not double the
## height of every step.
##
## Sits at 2 because the bowl is small next to a MAYHEM arena and gets blown up
## four to eight times to fit around one. At 1 the tiers read as flat plazas;
## this puts the rise back in proportion with the run. The real fix is a bowl
## authored at arena scale, and then this goes back to 1.
@export var height_scale: float = 2.0
## The bowl's pit is 2:1 and the arenas are square, so a per-axis fit stretches
## the terraces twice as deep on one side. Off (the default) that stretch is
## accepted, because from inside the pit a deeper terrace reads as a terrace and
## the stands stay close. On, the bowl is scaled evenly and the extra room shows
## up as pit floor around the arena instead.
@export var uniform_fit: bool = false

## Ring of slabs filling the pit floor between the arena and the first tier.
## Without it that gap reads as a moat of sky, because the arena's own floor
## stops at the last placed tile.
@export var build_apron: bool = true
## Matches the height of a greybox floor tile, so the apron meets the arena at
## the surface the player walks on rather than a step below it.
@export var apron_height: float = 0.75

@export_group("Perimeter")
## Invisible wall around the play area. Without it the arena's edge is a cliff
## into the stands, and the kill volume below turns a stray dash into a death.
@export var wall_height: float = 14.0
@export var wall_thickness: float = 2.0
## Deliberately outside the navigation bake: these are not level geometry, and a
## navmesh that knows about them tries to path along them.
@export var build_perimeter_walls: bool = true

@export_group("Material")
@export var concrete_texture: Texture2D
## Metres per texture tile. Triplanar, so stretching the bowl does not smear the
## slabs - they stay the same size whatever the arena is.
@export var concrete_tiling: float = 0.25
@export var concrete_color: Color = Color(0.72, 0.72, 0.70)
@export var concrete_roughness: float = 0.92
## Draws the stands from both sides.
##
## A stopgap, and it says so: the shipped bowl has a few hundred triangles whose
## normals point inwards, and Godot culls backfaces while Blender's viewport does
## not - so the model looks whole in Blender and full of holes in the game.
## Turning culling off fills the holes; it does not fix the lighting on those
## faces, because their normals still point the wrong way.
##
## `tools/measure_shell_pit.gd` reports the flipped count. Once Recalculate
## Outside has been run on the mesh, this goes back to false.
@export var double_sided: bool = true

@onready var _stands: Node3D = $Stands

var _walls: Node3D
var _apron: Node3D


func _ready() -> void:
	_apply_concrete()


## Fits the venue to this arena. `bounds` is the grid in metres, its origin at
## the floor of cell (0, 0, 0).
## `theme` is optional: given one, its pit measurement replaces the exports here.
func setup(bounds: AABB, theme: ArenaTheme = null) -> void:
	if theme != null:
		pit_size = theme.pit_size
		pit_center = theme.pit_center
	if _stands == null:
		_stands = get_node_or_null("Stands") as Node3D
	if _stands == null:
		push_error("ArenaShell: no Stands node to fit")
		return

	var wanted := Vector2(
		bounds.size.x + pit_margin * 2.0, bounds.size.z + pit_margin * 2.0)
	var scale_x: float = wanted.x / pit_size.x
	var scale_z: float = wanted.y / pit_size.y
	if uniform_fit:
		scale_x = maxf(scale_x, scale_z)
		scale_z = scale_x
	var fit := Vector3(scale_x, height_scale, scale_z)
	_stands.scale = fit
	# Land the pit's centre on the arena's centre: the pit is off-centre in the
	# model, and scaling moves it further off unless it is compensated here.
	var centre: Vector3 = bounds.position + bounds.size * 0.5
	_stands.position = Vector3(
		centre.x - pit_center.x * fit.x, bounds.position.y, centre.z - pit_center.y * fit.z)

	if build_apron:
		_build_apron(bounds, Vector2(pit_size.x * fit.x, pit_size.y * fit.z), centre)
	if build_perimeter_walls:
		_build_perimeter(bounds)


# Private

func _apply_concrete() -> void:
	var material: StandardMaterial3D = _concrete_material()
	for mesh: MeshInstance3D in _find_meshes(self):
		mesh.material_override = material


func _concrete_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = concrete_color
	material.albedo_texture = concrete_texture
	material.roughness = concrete_roughness
	material.metallic = 0.0
	# World-space triplanar: the bowl is scaled per arena, and without this the
	# slabs would be a different size in every one of them.
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * concrete_tiling
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if double_sided:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	var mesh := node as MeshInstance3D
	if mesh != null:
		found.append(mesh)
	for child: Node in node.get_children():
		found.append_array(_find_meshes(child))
	return found


## The pit floor, built as a ring of four slabs around the arena rather than one
## slab under it.
##
## A single slab was the first version and it z-fought the whole arena: the
## player's floor tiles and the apron are both `apron_height` tall and sit on the
## same plane, so every overlapping pixel flickered between the two. A ring never
## overlaps anything, which is cheaper than depth-biasing a lie.
##
## Visual only - it lives outside the perimeter wall, so nothing ever stands on
## it, and a collider there would only feed the navmesh bake.
func _build_apron(bounds: AABB, pit: Vector2, centre: Vector3) -> void:
	if _apron != null:
		_apron.queue_free()
	_apron = Node3D.new()
	_apron.name = "Apron"
	add_child(_apron)

	var material: StandardMaterial3D = _concrete_material()
	var band := Vector2(
		maxf((pit.x - bounds.size.x) * 0.5, 0.0),
		maxf((pit.y - bounds.size.z) * 0.5, 0.0))
	if band.x <= 0.0 and band.y <= 0.0:
		return
	var half := Vector2(bounds.size.x * 0.5, bounds.size.z * 0.5)
	# North and south run the full width; east and west fill what is left, so the
	# four pieces tile the ring without ever crossing each other.
	var sizes: Array[Vector3] = [
		Vector3(pit.x, apron_height, band.y),
		Vector3(pit.x, apron_height, band.y),
		Vector3(band.x, apron_height, bounds.size.z),
		Vector3(band.x, apron_height, bounds.size.z),
	]
	var offsets: Array[Vector3] = [
		Vector3(0.0, 0.0, -half.y - band.y * 0.5),
		Vector3(0.0, 0.0, half.y + band.y * 0.5),
		Vector3(-half.x - band.x * 0.5, 0.0, 0.0),
		Vector3(half.x + band.x * 0.5, 0.0, 0.0),
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
		slab.position = Vector3(centre.x, bounds.position.y + apron_height * 0.5, centre.z) 			+ offsets[index]
		_apron.add_child(slab)


## Four boxes at the edge of the play area. Collision only: no mesh, and outside
## the navigation source group, so they stop bodies without touching the bake.
func _build_perimeter(bounds: AABB) -> void:
	if _walls != null:
		_walls.queue_free()
	_walls = Node3D.new()
	_walls.name = "Perimeter"
	add_child(_walls)

	var centre: Vector3 = bounds.position + bounds.size * 0.5
	var half := Vector2(bounds.size.x * 0.5, bounds.size.z * 0.5)
	var offsets: Array[Vector3] = [
		Vector3(0.0, 0.0, -half.y - wall_thickness * 0.5),
		Vector3(0.0, 0.0, half.y + wall_thickness * 0.5),
		Vector3(-half.x - wall_thickness * 0.5, 0.0, 0.0),
		Vector3(half.x + wall_thickness * 0.5, 0.0, 0.0),
	]
	var sizes: Array[Vector3] = [
		Vector3(bounds.size.x + wall_thickness * 2.0, wall_height, wall_thickness),
		Vector3(bounds.size.x + wall_thickness * 2.0, wall_height, wall_thickness),
		Vector3(wall_thickness, wall_height, bounds.size.z),
		Vector3(wall_thickness, wall_height, bounds.size.z),
	]
	for index: int in offsets.size():
		var body := StaticBody3D.new()
		body.name = "Wall%d" % index
		var shape := BoxShape3D.new()
		shape.size = sizes[index]
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		body.position = Vector3(centre.x, bounds.position.y + wall_height * 0.5, centre.z) \
			+ offsets[index]
		_walls.add_child(body)
