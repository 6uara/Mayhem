@tool
extends SceneTree
## Measures a stands model for `ArenaShell`, and checks it for the two things
## that make a bowl look wrong in the game but fine in Blender.
##
##   godot --headless --path . -s tools/measure_shell_pit.gd
##   MAYHEM_MODEL=res://path/to/other.blend godot --headless ... (to measure another)
##
## Prints the `pit_size` and `pit_center` to paste into the shell, the height
## profile of each side (a closed bowl rises on all four), and how many triangles
## face down - a bowl with more downward than upward faces has inverted normals,
## which Godot renders as holes because it culls backfaces and Blender does not.

const DEFAULT_MODEL: String = "res://assets/models/arena/Stands.blend"
## Sampling step for the pit search, in metres.
const STEP: float = 0.5


func _initialize() -> void:
	var path: String = OS.get_environment("MAYHEM_MODEL")
	if path == "":
		path = DEFAULT_MODEL
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("measure_shell_pit: could not load %s" % path)
		quit(1)
		return

	var root: Node3D = scene.instantiate() as Node3D
	var mesh_instance: MeshInstance3D = _first_mesh(root)
	if mesh_instance == null:
		push_error("measure_shell_pit: no MeshInstance3D in %s" % path)
		quit(1)
		return

	var xform: Transform3D = mesh_instance.transform
	var faces: PackedVector3Array = mesh_instance.mesh.get_faces()
	print("model: %s" % path)
	print("  object scale: %v  (apply it in Blender if it is not 1,1,1)" % mesh_instance.scale)
	print("  triangles: %d" % (faces.size() / 3))
	var bounds: AABB = _world_bounds(xform, faces)
	print("  bounds: pos=%v size=%v" % [bounds.position, bounds.size])
	print("  meshes in the scene: %d" % _count_meshes(root))

	_report_normals(xform, faces)
	var pit: Rect2 = _measure_pit(xform, faces)
	# A pit that reaches the model's own edge is not a pit: this is a section to
	# be tiled, not a bowl to be fitted around an arena.
	if pit.size.x < 1.0 or pit.size.y < 1.0 or pit.size.x >= bounds.size.x * 0.95 			or pit.size.y >= bounds.size.z * 0.95:
		print("  no enclosed pit: this reads as a section to tile, not a bowl")
		quit(0)
		return
	print("  pit_size = Vector2(%.2f, %.2f)" % [pit.size.x, pit.size.y])
	print("  pit_center = Vector2(%.2f, %.2f)" % [
		pit.position.x + pit.size.x * 0.5, pit.position.y + pit.size.y * 0.5])
	_report_profile(xform, faces, pit.get_center())
	quit(0)


# Private

func _world_bounds(xform: Transform3D, faces: PackedVector3Array) -> AABB:
	var bounds := AABB()
	var first: bool = true
	for vertex: Vector3 in faces:
		var world: Vector3 = xform * vertex
		if first:
			bounds = AABB(world, Vector3.ZERO)
			first = false
		else:
			bounds = bounds.expand(world)
	return bounds


func _count_meshes(node: Node) -> int:
	var total: int = 1 if node is MeshInstance3D else 0
	for child: Node in node.get_children():
		total += _count_meshes(child)
	return total


func _first_mesh(node: Node) -> MeshInstance3D:
	var mesh := node as MeshInstance3D
	if mesh != null:
		return mesh
	for child: Node in node.get_children():
		var found: MeshInstance3D = _first_mesh(child)
		if found != null:
			return found
	return null


## Grows a rectangle out from the middle until it hits geometry: that empty
## middle is the pit the arena sits in.
func _measure_pit(xform: Transform3D, faces: PackedVector3Array) -> Rect2:
	var occupied: Dictionary = {}
	for i: int in range(0, faces.size(), 3):
		var a: Vector3 = xform * faces[i]
		var b: Vector3 = xform * faces[i + 1]
		var c: Vector3 = xform * faces[i + 2]
		for point: Vector3 in [a, b, c, (a + b + c) / 3.0]:
			occupied[Vector2i(int(floor(point.x / STEP)), int(floor(point.z / STEP)))] = true

	# Bounded by the model's own footprint: a section model has no enclosed hole,
	# and without a stop the search grows into empty space forever.
	var extent: Rect2i = _occupied_bounds(occupied)
	var seed_cell: Vector2i = _find_seed(occupied)
	var low: Vector2i = seed_cell
	var high: Vector2i = seed_cell
	var growing: bool = true
	while growing:
		growing = false
		for side: int in 4:
			if low.x <= extent.position.x and high.x >= extent.end.x 					and low.y <= extent.position.y and high.y >= extent.end.y:
				growing = false
				break
			var next_low := Vector2i(
				low.x - (1 if side == 0 else 0), low.y - (1 if side == 2 else 0))
			var next_high := Vector2i(
				high.x + (1 if side == 1 else 0), high.y + (1 if side == 3 else 0))
			if not extent.has_point(next_low) or not extent.has_point(next_high):
				continue
			if not _is_clear(occupied, next_low, next_high):
				continue
			low = next_low
			high = next_high
			growing = true
	return Rect2(Vector2(low) * STEP, Vector2(high - low + Vector2i.ONE) * STEP)


## The emptiest cell nearest the middle of the model's footprint.
func _find_seed(occupied: Dictionary) -> Vector2i:
	var bounds: Rect2i = _occupied_bounds(occupied)
	var centre: Vector2i = bounds.position + bounds.size / 2
	if not occupied.has(centre):
		return centre
	for radius: int in range(1, 40):
		for dx: int in range(-radius, radius + 1):
			for dz: int in range(-radius, radius + 1):
				var candidate := centre + Vector2i(dx, dz)
				if not occupied.has(candidate):
					return candidate
	return centre


func _occupied_bounds(occupied: Dictionary) -> Rect2i:
	var bounds := Rect2i()
	var first: bool = true
	for cell: Vector2i in occupied.keys():
		if first:
			bounds = Rect2i(cell, Vector2i.ZERO)
			first = false
		else:
			bounds = bounds.expand(cell)
	return bounds


func _is_clear(occupied: Dictionary, low: Vector2i, high: Vector2i) -> bool:
	for x: int in range(low.x, high.x + 1):
		for z: int in range(low.y, high.y + 1):
			if occupied.has(Vector2i(x, z)):
				return false
	return true


## More downward than upward faces means flipped normals: Godot culls those and
## the bowl comes out with holes even though Blender shows it whole.
func _report_normals(xform: Transform3D, faces: PackedVector3Array) -> void:
	var up: int = 0
	var side: int = 0
	var down: int = 0
	for i: int in range(0, faces.size(), 3):
		var a: Vector3 = xform * faces[i]
		var b: Vector3 = xform * faces[i + 1]
		var c: Vector3 = xform * faces[i + 2]
		var normal: Vector3 = (b - a).cross(c - a).normalized()
		if normal.y > 0.5:
			up += 1
		elif normal.y < -0.5:
			down += 1
		else:
			side += 1
	print("  normals: up=%d side=%d down=%d" % [up, side, down])
	if down > up:
		print("  WARNING: more faces point down than up. In Blender: Edit Mode, "
			+ "select all, Mesh > Normals > Recalculate Outside (Shift+N), and check "
			+ "with Overlays > Face Orientation.")


## Height reached at each distance from the pit, per side. A closed bowl climbs
## on all four; a side that stays flat is a side with no tiers.
func _report_profile(xform: Transform3D, faces: PackedVector3Array, pit_centre: Vector2) -> void:
	var profiles: Dictionary = {"-X": {}, "+X": {}, "-Z": {}, "+Z": {}}
	for vertex: Vector3 in faces:
		var world: Vector3 = xform * vertex
		var offset := Vector2(world.x - pit_centre.x, world.z - pit_centre.y)
		var key: String = ""
		var distance: int = 0
		if absf(offset.x) > absf(offset.y):
			key = "+X" if offset.x > 0.0 else "-X"
			distance = int(absf(offset.x) / 4.0)
		else:
			key = "+Z" if offset.y > 0.0 else "-Z"
			distance = int(absf(offset.y) / 4.0)
		var bucket: Dictionary = profiles[key]
		bucket[distance] = maxf(float(bucket.get(distance, 0.0)), world.y)

	print("  height every 4m out from the pit:")
	for key: String in ["-X", "+X", "-Z", "+Z"]:
		var bucket: Dictionary = profiles[key]
		var distances: Array = bucket.keys()
		distances.sort()
		var line: String = ""
		for distance: int in distances:
			line += " %4.1f" % float(bucket[distance])
		print("    %s:%s" % [key, line])
