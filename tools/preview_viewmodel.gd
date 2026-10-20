extends SceneTree
## Renderiza el viewmodel (arma + brazos) como lo ve el jugador, a PNG.
##
##   godot --path . -s res://tools/preview_viewmodel.gd -- rifle_ak
##   godot --path . -s res://tools/preview_viewmodel.gd -- pistol reload 0.4
##   godot --path . -s res://tools/preview_viewmodel.gd -- smg equip 0.5
##
## Sale a user://viewmodel_preview.png (la ruta absoluta se imprime). Misma camara
## y mismo FOV que ViewmodelRig, sin el resto del juego: sirve para ajustar las
## constantes de ViewmodelArms mirando, que es la unica forma de ajustarlas.
##
## Igual que preview_enemy_model.gd corre con ventana, y Godot puede re-serializar
## escenas en esa pasada: mira git status despues.

const OUTPUT: String = "user://viewmodel_preview.png"
const FOV: float = 62.0
## Por load() y no preload: los brazos usan autoloads (EventBus, Tokens), y un
## script de SceneTree se compila antes de que esten registrados.
const ARMS_PATH: String = "res://scripts/components/viewmodel_arms.gd"

var _frames: int = 0
var _arms: Node3D
var _equip_time: float = 0.32
var _pivot: Node3D
var _state: String = "idle"
var _progress: float = 0.5


func _initialize() -> void:
	var weapon_id: String = "rifle_ak"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		weapon_id = args[0]
	if args.size() > 1:
		_state = args[1]
	if args.size() > 2:
		_progress = float(args[2])

	var world := Node3D.new()
	get_root().add_child(world)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.32, 0.34, 0.38)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	world.add_child(world_environment)

	var camera := Camera3D.new()
	camera.fov = FOV
	camera.near = 0.01
	world.add_child(camera)
	camera.current = true
	var key := DirectionalLight3D.new()
	key.transform = Transform3D(Basis(Vector3(0.86, -0.25, 0.44), Vector3(0, 0.87, 0.5),
		Vector3(-0.51, -0.43, 0.75)), Vector3(0, 2, 0))
	key.light_energy = 1.6
	world.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0.4, 0.3, 0.2)
	fill.light_energy = 1.2
	fill.omni_range = 4.0
	camera.add_child(fill)

	var data: WeaponData = load("res://data/weapons/%s.tres" % weapon_id)
	_pivot = Node3D.new()
	camera.add_child(_pivot)
	_pivot.position = data.viewmodel_offset
	var model: Node3D = data.viewmodel.instantiate()
	_pivot.add_child(model)
	model.rotation_degrees = data.viewmodel_rotation_degrees
	model.scale = Vector3.ONE * data.viewmodel_scale

	var arms_script: GDScript = load(ARMS_PATH)
	_arms = arms_script.new()
	_equip_time = arms_script.get_script_constant_map()["EQUIP_TIME"]
	camera.add_child(_arms)
	_arms.position = data.viewmodel_offset
	_arms.call(&"build", _bounds(model), data.viewmodel_offset)
	# "side" y "top" miran desde afuera, para ver codos y muñecas.
	for view: String in ["side", "top"]:
		if not args.has(view):
			continue
		var outside := Camera3D.new()
		outside.fov = 50.0
		world.add_child(outside)
		var eye: Vector3 = Vector3(1.4, -0.15, -0.3) if view == "side" else Vector3(0.0, 1.3, -0.3)
		outside.look_at_from_position(eye, Vector3(0.0, -0.2, -0.3),
			Vector3.UP if view == "side" else Vector3.FORWARD)
		outside.current = true
	if _state == "reload":
		_arms.call(&"set_reload_progress", _progress)
		# El arma gira en la recarga igual que en WeaponComponent.
		_pivot.rotation_degrees.x = -360.0 * smoothstep(0.0, 1.0, _progress)


func _process(_delta: float) -> bool:
	_frames += 1
	if _state == "equip":
		_arms.set(&"_equip_left", _equip_time * (1.0 - _progress))
	else:
		_arms.set(&"_equip_left", 0.0)
	if _frames == 18 and OS.get_cmdline_user_args().has("debug"):
		var skeleton := _arms.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		# Lo que deja un modificador solo existe hasta el fin del update del
		# esqueleto: hay que leerlo ahi, no despues.
		skeleton.skeleton_updated.connect(_print_debug.bind(skeleton), CONNECT_ONE_SHOT)
	if _frames < 20:
		return false
	var image: Image = get_root().get_texture().get_image()
	image.save_png(OUTPUT)
	print("viewmodel preview: ", ProjectSettings.globalize_path(OUTPUT))
	return true


## Objetivos contra donde quedaron los huesos, en el espacio de los brazos.
func _print_debug(skeleton: Skeleton3D) -> void:
	var to_arms: Transform3D = _arms.global_transform.affine_inverse() * skeleton.global_transform
	print("targets ", _arms.call(&"get_wrist_targets"))
	for bone_name: String in ["upper_arm.R", "forearm.R", "hand.R", "upper_arm.L", "forearm.L",
			"hand.L", "f_middle.01.R", "f_middle.01.L"]:
		var bone: int = skeleton.find_bone(bone_name)
		print(bone_name, " ", to_arms * skeleton.get_bone_global_pose(bone).origin)


func _bounds(model: Node3D) -> AABB:
	var out := AABB()
	var found: bool = false
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var t := Transform3D.IDENTITY
		var walker: Node3D = mesh_instance
		while walker != null and walker != model:
			t = walker.transform * t
			walker = walker.get_parent() as Node3D
		var local: AABB = t * mesh_instance.mesh.get_aabb()
		out = local if not found else out.merge(local)
		found = true
	return model.transform * out if found else AABB()
