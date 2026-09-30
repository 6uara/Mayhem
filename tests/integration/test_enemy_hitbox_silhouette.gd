extends GutTest
## The hitbox has to cover what the player sees.
##
## `EnemyData.hitbox_radius` defaults to 0, which falls back to `collision_radius` -
## the navmesh number, sized for doorways and not for bullets. A model wider than
## that radius is a model whose outer part is quietly bulletproof, and nothing on
## screen says so: the shot visibly lands and does nothing. The Summoner shipped
## like that for a while, with 35cm a side of its base not registering.
##
## Every archetype is measured from what is actually drawn - the model when it has
## one, the grey-box mesh when it does not - so a new model or a resized primitive
## re-checks itself without anyone remembering to.

const ARCHETYPES: Array[String] = [
	"rusher", "ranger", "flyer", "bomber",
	"elite", "environmental", "healer", "summoner",
]

## The share of the drawn vertices that has to fall inside the hitbox radius.
##
## Not all of them: real models have thin extremities - a gun barrel, a leg tip, a
## wing - that nobody aims at and that would make the hitbox a barn door if it had
## to reach them. The bounding box was tried first and it is exactly that: the
## Ranger's arms alone asked for 0.73m. Three quarters of the geometry is the body
## mass - what the player actually puts the reticle on.
##
## Measured when this was written (radius of that 75th vertex -> hitbox):
## rusher 0.59 -> 0.60, ranger 0.42 -> 0.45, flyer 0.45 -> 0.55,
## bomber 0.50 -> 0.70, elite 0.75 -> 1.00, environmental 0.54 -> 0.60,
## healer 0.22 -> 0.45, summoner 0.76 -> 0.80.
const COVERED_FRACTION: float = 0.75


func _spawn(id: String) -> Enemy:
	var enemy: Enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	add_child_autofree(enemy)
	await wait_physics_frames(1)
	enemy.setup(load("res://data/enemies/%s.tres" % id), Vector3.ZERO)
	await wait_physics_frames(1)
	return enemy


## Horizontal distance from the body's vertical axis - the axis the hitbox capsule
## stands on - of every vertex that is drawn, sorted.
func _drawn_radii(enemy: Enemy) -> PackedFloat32Array:
	var meshes: Array[MeshInstance3D] = []
	if enemy.data.model_scene != null:
		meshes = enemy._model_meshes
	elif enemy.mesh_instance != null:
		meshes = [enemy.mesh_instance]
	var to_body: Transform3D = enemy.global_transform.affine_inverse()
	var radii := PackedFloat32Array()
	for mesh_node: MeshInstance3D in meshes:
		if mesh_node.mesh == null or not mesh_node.is_visible_in_tree():
			continue
		var to_body_from_mesh: Transform3D = to_body * mesh_node.global_transform
		for vertex: Vector3 in mesh_node.mesh.get_faces():
			var local: Vector3 = to_body_from_mesh * vertex
			radii.append(Vector2(local.x, local.z).length())
	radii.sort()
	return radii


func test_every_archetypes_hitbox_covers_its_silhouette() -> void:
	for id: String in ARCHETYPES:
		var enemy: Enemy = await _spawn(id)
		var radii: PackedFloat32Array = _drawn_radii(enemy)
		var hitbox: float = enemy.get_hitbox_radius()
		assert_gt(radii.size(), 0, "%s: something is drawn to measure" % id)
		if radii.is_empty():
			continue
		var body: float = radii[int(radii.size() * COVERED_FRACTION)]
		assert_true(hitbox >= body,
			"%s: hitbox radius %.2f leaves the body bulletproof - %d%% of what is drawn reaches %.2f"
				% [id, hitbox, int(COVERED_FRACTION * 100.0), body])
		enemy.queue_free()
		await wait_physics_frames(1)
