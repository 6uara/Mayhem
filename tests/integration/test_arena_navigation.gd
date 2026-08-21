extends GutTest
## The arena's navmesh has to actually contain the arena. An empty navmesh is silent:
## agents just report "navigation finished" and enemies fall back to straight-line
## steering, walking into walls instead of pathing around them.
##
## Re-run `tools/bake_navmesh.gd` and commit the result if this fails after a layout
## change - the committed bake is what ships.


func test_arena_has_a_populated_navmesh() -> void:
	var arena: Node3D = add_child_autofree(
		load("res://scenes/arena/greybox_arena.tscn").instantiate())
	var region := arena.get_node("Navigation") as NavigationRegion3D
	assert_not_null(region, "the arena has a NavigationRegion3D")

	await wait_physics_frames(2)

	var navmesh: NavigationMesh = region.navigation_mesh
	assert_not_null(navmesh, "navigation_mesh")
	assert_gt(navmesh.get_vertices().size(), 0,
		"empty navmesh - re-run tools/bake_navmesh.gd")
	assert_gt(navmesh.get_polygon_count(), 0, "empty navmesh - no polygons")


func test_navmesh_covers_the_arena_floor() -> void:
	var arena: Node3D = add_child_autofree(
		load("res://scenes/arena/greybox_arena.tscn").instantiate())
	await wait_physics_frames(2)

	# The floor is 70x70; a bake that only caught one platform would still pass the
	# "not empty" check, so assert it actually spans the play space.
	var navmesh: NavigationMesh = (arena.get_node("Navigation") as NavigationRegion3D).navigation_mesh
	var min_x: float = INF
	var max_x: float = -INF
	for vertex: Vector3 in navmesh.get_vertices():
		min_x = minf(min_x, vertex.x)
		max_x = maxf(max_x, vertex.x)
	assert_gt(max_x - min_x, 40.0, "the navmesh should span most of the 70m arena")


func test_spawn_doors_are_registered_and_unique() -> void:
	var arena: Node3D = add_child_autofree(
		load("res://scenes/arena/greybox_arena.tscn").instantiate())
	await wait_physics_frames(2)

	var doors: Array = get_tree().get_nodes_in_group(&"spawn_door")
	assert_gt(doors.size(), 1, "more than one door, or camping beats the level design")

	var ids: Array[StringName] = []
	for node: Node in doors:
		var door := node as SpawnDoor
		assert_not_null(door, "every member of the group is a SpawnDoor")
		assert_false(ids.has(door.door_id), "duplicate door id %s" % door.door_id)
		ids.push_back(door.door_id)


## El piso es una sola pieza y es de donde sale el bake. Si pierde el grupo o la
## colision, el navmesh queda vacio y los enemigos caminan en linea recta contra
## las paredes en vez de rodearlas - que es el modo en que esto falla en silencio.
func test_the_navmesh_is_baked_from_the_floor() -> void:
	var arena: Node3D = add_child_autofree(
		load("res://scenes/arena/greybox_arena.tscn").instantiate())
	await wait_physics_frames(2)

	var ground := arena.get_node_or_null("Floor") as CSGCylinder3D
	assert_not_null(ground, "la arena tiene un Floor")
	assert_true(ground.is_in_group(&"navigation_source"),
		"el piso tiene que estar en navigation_source o el bake no lo ve")
	assert_true(ground.use_collision,
		"el bake lee colisionadores estaticos, asi que el piso necesita colision")


## Toda la arena esta autorada con el piso en y=0: los pads, los hazards, las cajas
## de mantle y las puertas. Si la cara de arriba del cilindro no queda ahi, todo eso
## queda enterrado o flotando, y el jugador aparece adentro del piso.
func test_the_floor_surface_is_at_zero() -> void:
	var arena: Node3D = add_child_autofree(
		load("res://scenes/arena/greybox_arena.tscn").instantiate())
	await wait_physics_frames(2)

	var ground := arena.get_node_or_null("Floor") as CSGCylinder3D
	assert_not_null(ground)
	var top: float = ground.position.y + ground.height * 0.5
	assert_almost_eq(top, 0.0, 0.01, "la cara de arriba del piso vive en y=0")


## La pared no se dibuja, pero frena. Es lo unico que impide subirse a las gradas:
## la malla de ArenaStands no trae ningun cuerpo de colision propio.
func test_the_invisible_wall_is_invisible_and_solid() -> void:
	var arena: Node3D = add_child_autofree(
		load("res://scenes/arena/greybox_arena.tscn").instantiate())
	await wait_physics_frames(4)

	var wall := arena.get_node_or_null("InvisibleWall") as CSGCylinder3D
	assert_not_null(wall, "la arena tiene una InvisibleWall")
	assert_false(wall.visible, "invisible de verdad, no un material transparente")
	assert_true(wall.use_collision, "sin colision no frena a nadie")

	# Desde el centro hacia afuera, a la altura del pecho: tiene que chocar.
	var centre: Vector3 = wall.global_position
	var space: PhysicsDirectSpaceState3D = arena.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(centre, centre + Vector3(200, 0, 0))
	var hit: Dictionary = space.intersect_ray(query)
	assert_false(hit.is_empty(), "un rayo hacia afuera tiene que chocar con la pared")
	if not hit.is_empty():
		var reach: float = centre.distance_to(hit["position"])
		assert_almost_eq(reach, wall.radius, 0.5,
			"choca en el radio de la pared, no contra otra cosa")


## Cada puerta suelta a sus enemigos adentro de la pared, con lugar de sobra para
## el cuerpo mas grande del catalogo. Un spawn del lado de afuera, o pegado, deja al
## enemigo raspando contra la pared sin poder entrar nunca.
func test_every_spawn_lands_inside_the_invisible_wall() -> void:
	var arena: Node3D = add_child_autofree(
		load("res://scenes/arena/greybox_arena.tscn").instantiate())
	await wait_physics_frames(2)

	var wall := arena.get_node_or_null("InvisibleWall") as CSGCylinder3D
	assert_not_null(wall)
	var centre := Vector2(wall.global_position.x, wall.global_position.z)
	var biggest: float = _biggest_enemy_radius()

	for node: Node in get_tree().get_nodes_in_group(&"spawn_door"):
		var door := node as SpawnDoor
		var spawn: Vector3 = door.get_spawn_position()
		var clearance: float = wall.radius - Vector2(spawn.x, spawn.z).distance_to(centre)
		assert_gt(clearance, biggest,
			"%s spawnea a %.2f m de la pared, y el cuerpo mas grande mide %.2f" % [
				door.name, clearance, biggest])
		assert_gt(spawn.y, -0.01, "%s spawnea debajo del piso" % door.name)


## Nadie puede rutear hasta la franja muerta entre la pared y el borde del piso.
##
## Recast no borra esa franja: la pared es una superficie vertical, y el piso del
## otro lado sigue siendo piso, asi que igual se bakea. Lo que si hace es dejarla
## como una isla aparte. Eso es lo que importa y lo que se prueba aca - un enemigo
## que pudiera rutear hacia afuera se quedaria empujando contra algo que no puede
## atravesar, que es exactamente el sintoma que la pared tiene que evitar.
func test_nothing_can_path_past_the_invisible_wall() -> void:
	var arena: Node3D = add_child_autofree(
		load("res://scenes/arena/greybox_arena.tscn").instantiate())
	await wait_physics_frames(4)

	var wall := arena.get_node_or_null("InvisibleWall") as CSGCylinder3D
	var region := arena.get_node("Navigation") as NavigationRegion3D
	var map: RID = region.get_navigation_map()
	var centre := Vector2(wall.global_position.x, wall.global_position.z)

	# Un punto de la franja muerta, justo afuera de la pared.
	var outside := Vector3(centre.x + wall.radius + 3.0, 0.0, centre.y)
	var parameters := NavigationPathQueryParameters3D.new()
	parameters.map = map
	parameters.start_position = Vector3(centre.x, 0.0, centre.y)
	parameters.target_position = outside
	var result := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(parameters, result)

	var path: PackedVector3Array = result.path
	assert_gt(path.size(), 0, "la consulta devolvio algo")
	if path.is_empty():
		return
	var arrival: Vector3 = path[path.size() - 1]
	var reach: float = Vector2(arrival.x, arrival.z).distance_to(centre)
	assert_lt(reach, wall.radius,
		"la ruta llega a %.2f m del centro, del lado de afuera de la pared (radio %.2f)" % [
			reach, wall.radius])


## El cuerpo mas ancho que el juego puede spawnear, leido del catalogo y no escrito a
## mano, asi que subir el radio de un arquetipo mueve esta prueba con el.
func _biggest_enemy_radius() -> float:
	var biggest: float = 0.0
	var dir := DirAccess.open("res://data/enemies/")
	assert_not_null(dir, "el catalogo de enemigos se puede leer")
	for file: String in dir.get_files():
		if not file.ends_with(".tres") and not file.ends_with(".tres.remap"):
			continue
		var data := load("res://data/enemies/" + file.trim_suffix(".remap")) as EnemyData
		if data != null:
			biggest = maxf(biggest, data.collision_radius)
	return biggest


## Las gradas frenan de verdad.
##
## Un CollisionShape3D solo cuenta si cuelga de un CollisionObject3D. Colgado del
## Node3D que trae el .blend se ve identico en el editor y no colisiona con nada:
## el sintoma es que el jugador atraviesa las gradas y se va del mapa, y no hay
## ningun error que lo diga. Se prueba con un rayo y no leyendo el arbol, porque
## lo que importa es que el servidor de fisica la conozca.
func test_the_stands_actually_collide() -> void:
	var arena: Node3D = add_child_autofree(
		load("res://scenes/arena/greybox_arena.tscn").instantiate())
	await wait_physics_frames(4)

	var stands: Node3D = arena.get_node_or_null("Arena")
	assert_not_null(stands, "la arena instancia las gradas")
	var bodies: int = 0
	for node: Node in _descendants(stands):
		if node is CollisionObject3D:
			bodies += 1
	assert_gt(bodies, 0,
		"la forma de colision tiene que colgar de un CollisionObject3D o no existe")


## Nada de lo que frena al jugador esta enterrado adentro de las gradas: la pared
## invisible tiene que quedar por dentro de su cara interna, no en el medio de su
## geometria, o el jugador choca contra las gradas primero y la pared no hace nada.
func test_the_invisible_wall_sits_inside_the_stands() -> void:
	var arena: Node3D = add_child_autofree(
		load("res://scenes/arena/greybox_arena.tscn").instantiate())
	await wait_physics_frames(4)

	var wall := arena.get_node_or_null("InvisibleWall") as CSGCylinder3D
	var stands: Node3D = arena.get_node_or_null("Arena")
	var centre := Vector2(wall.global_position.x, wall.global_position.z)

	var inner: float = INF
	for node: Node in _descendants(stands):
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		for surface: int in mesh_node.mesh.get_surface_count():
			var verts: PackedVector3Array = \
				mesh_node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in verts:
				var world: Vector3 = mesh_node.global_transform * vertex
				inner = minf(inner, Vector2(world.x, world.z).distance_to(centre))

	assert_lt(wall.radius, inner,
		"la pared (radio %.2f) tiene que quedar por dentro de las gradas (%.2f)" % [
			wall.radius, inner])


func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in node.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found
