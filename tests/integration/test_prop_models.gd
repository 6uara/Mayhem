extends GutTest
## Los props con modelo (assets/models/props/, de tools/blender/build_props.py).
## Que se vean bien lo dice una captura; lo que se fija aca es que cambiar la
## caja primitiva por un modelo no rompio los nodos que los scripts usan.


func test_the_ammo_crate_still_hides_when_taken() -> void:
	var pickup: AmmoPickup = add_child_autofree(
		load("res://scenes/arena/ammo_pickup.tscn").instantiate())
	assert_not_null(pickup.mesh, "el modelo cuelga de `mesh`")
	assert_gt(pickup.mesh.find_children("*", "MeshInstance3D", true, false).size(), 0,
		"y es el modelo, no una caja vacia")
	pickup._set_available(false)
	assert_false(pickup.mesh.visible, "tomada, la caja desaparece")


func test_the_spawn_door_flashes_its_model() -> void:
	var door: SpawnDoor = add_child_autofree(
		load("res://scenes/arena/spawn_door.tscn").instantiate())
	assert_not_null(door.frame_mesh, "frame_mesh apunta a la malla del modelo")
	assert_not_null(door._material, "y tiene un material propio para encenderse")


func test_the_bounce_pad_pulses_its_model() -> void:
	var pad: BouncePad = add_child_autofree(
		load("res://scenes/arena/bounce_pad.tscn").instantiate())
	pad._pulse()
	assert_ne(pad._mesh.scale, Vector3.ONE, "el pad se aplasta al lanzar")


## La pantalla cuelga bajo el techo y por encima de todo lo que se puede pisar.
func test_the_coliseum_hangs_the_jumbotron_under_the_roof() -> void:
	var shell: Node3D = add_child_autofree(
		load("res://scenes/arena/shells/coliseum_shell.tscn").instantiate())
	var bounds := AABB(Vector3(-2.0, 0.0, -2.0), Vector3(64.0, 15.0, 64.0))
	shell.call(&"setup", bounds)
	var jumbotron := shell.find_child("Jumbotron", true, false) as Node3D
	assert_not_null(jumbotron, "hay pantalla")
	var roof: ArenaRoof = shell.get(&"roof")
	assert_lt(jumbotron.position.y, roof.get_height(), "debajo del techo")
	assert_gt(jumbotron.position.y, bounds.end.y, "y arriba de la arena")


## El ancla y la plataforma conservan la textura del modelo: el telegrafo va
## encima como brillo aditivo, no en lugar de ella.
func test_textured_interactables_glow_over_their_texture() -> void:
	for path: String in ["res://scenes/arena/grapple_anchor.tscn",
			"res://scenes/arena/moving_platform.tscn"]:
		var root: Node3D = add_child_autofree((load(path) as PackedScene).instantiate())
		var telegraph: TelegraphComponent = root.get_node(^"Telegraph")
		assert_true(telegraph.overlay, "%s: telegrafo en overlay" % path)
		assert_gt(telegraph.meshes.size(), 0, "%s: maneja la malla del modelo" % path)
		var mesh: MeshInstance3D = telegraph.meshes[0]
		assert_null(mesh.material_override, "%s: la textura queda" % path)
		var glow := mesh.material_overlay as StandardMaterial3D
		assert_not_null(glow, "%s: el brillo va encima" % path)
		assert_eq(glow.emission, telegraph.get_color(), "%s: con el color de la ley" % path)


## Con mapa de brillo, el overlay pulsa solo en las franjas: parejo sobre toda la
## malla tapaba la textura del gancho con un violeta liso.
func test_the_anchor_glow_follows_the_models_glow_map() -> void:
	var anchor: GrappleAnchor = add_child_autofree(
		load("res://scenes/arena/grapple_anchor.tscn").instantiate())
	var glow := anchor.telegraph.meshes[0].material_overlay as StandardMaterial3D
	assert_not_null(glow.emission_texture, "usa el mapa de brillo del modelo")
	assert_eq(glow.emission_operator, BaseMaterial3D.EMISSION_OP_MULTIPLY,
		"y lo multiplica, no lo suma")


## El ancla tiene color propio y su propia luz, que se enciende mas en rango.
func test_the_grapple_anchor_glows_violet() -> void:
	var anchor: GrappleAnchor = add_child_autofree(
		load("res://scenes/arena/grapple_anchor.tscn").instantiate())
	assert_eq(anchor.telegraph.get_color(), Tokens.WORLD_GRAPPLE, "telegrafo violeta")
	assert_not_null(anchor.light, "trae luz")
	assert_eq(anchor.light.light_color, Tokens.WORLD_GRAPPLE, "del mismo color")
	assert_ne(Tokens.WORLD_GRAPPLE, Tokens.WORLD_TRAVERSAL, "y no es el cyan de lo usable")
	assert_gt(anchor.light_available_energy, anchor.light_idle_energy,
		"en rango brilla mas")
