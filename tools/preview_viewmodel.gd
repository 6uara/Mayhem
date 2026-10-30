extends SceneTree
## Renderiza el viewmodel (brazos y arma, una sola malla) como lo ve el jugador, a PNG.
##
##   godot --path . -s res://tools/preview_viewmodel.gd -- rifle_ak
##   godot --path . -s res://tools/preview_viewmodel.gd -- pistol reload 0.4
##   godot --path . -s res://tools/preview_viewmodel.gd -- smg equip 0.5
##   godot --path . -s res://tools/preview_viewmodel.gd -- shotgun grapple
##   godot --path . -s res://tools/preview_viewmodel.gd -- rifle_ak side
##
## Sale a user://viewmodel_preview.png, o a la ruta que se pase con `out=`. Mismo
## FOV que ViewmodelRig y un WeaponComponent de verdad, asi que lo que se ve es la
## pose del juego en ese estado. `side` y `top` miran desde afuera.
##
## Igual que preview_enemy_model.gd corre con ventana, y Godot puede re-serializar
## escenas en esa pasada: mira git status despues.

const OUTPUT: String = "user://viewmodel_preview.png"
const FOV: float = 62.0
## Por load() y no preload: el componente usa autoloads (EventBus, Tokens), y un
## script de SceneTree se compila antes de que esten registrados.
const WEAPON_PATH: String = "res://scripts/components/weapon_component.gd"

var _frames: int = 0
var _camera: Camera3D
var _world: Node3D
var _weapon: Node3D
var _weapon_id: String = "rifle_ak"
var _state: String = "idle"
var _progress: float = 0.5
var _output: String = OUTPUT


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var positional: Array[String] = []
	for argument: String in args:
		if argument.begins_with("out="):
			_output = argument.trim_prefix("out=")
		else:
			positional.append(argument)
	if positional.size() > 0:
		_weapon_id = positional[0]
	if positional.size() > 1:
		_state = positional[1]
	if positional.size() > 2:
		_progress = float(positional[2])

	_world = Node3D.new()
	get_root().add_child(_world)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.32, 0.34, 0.38)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_world.add_child(world_environment)

	_camera = Camera3D.new()
	_camera.fov = FOV
	_camera.near = 0.01
	_world.add_child(_camera)
	_camera.current = true
	var key := DirectionalLight3D.new()
	key.transform = Transform3D(Basis(Vector3(0.86, -0.25, 0.44), Vector3(0, 0.87, 0.5),
		Vector3(-0.51, -0.43, 0.75)), Vector3(0, 2, 0))
	key.light_energy = 1.6
	_world.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0.4, 0.3, 0.2)
	fill.light_energy = 1.2
	fill.omni_range = 4.0
	_camera.add_child(fill)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_build_weapon()
	if _frames == 2:
		_pose()
	if _frames < 20:
		return false
	var image: Image = get_root().get_texture().get_image()
	image.save_png(_output)
	print("viewmodel preview: ", ProjectSettings.globalize_path(_output))
	return true


func _build_weapon() -> void:
	var data: Resource = load("res://data/weapons/%s.tres" % _weapon_id)
	var script: GDScript = load(WEAPON_PATH)
	_weapon = script.new()
	_weapon.set(&"data", data)
	_weapon.set(&"viewmodel_parent", _camera)
	_weapon.set(&"idle_breath_height", 0.0)
	_weapon.set(&"idle_breath_roll_degrees", 0.0)
	_world.add_child(_weapon)
	var views: Dictionary = {
		"side": [Vector3(1.4, -0.15, -0.3), Vector3(0.0, -0.2, -0.3)],
		"top": [Vector3(0.0, 1.3, -0.3), Vector3(0.0, -0.2, -0.3)],
	}
	for view: String in views:
		if _state != view:
			continue
		var outside := Camera3D.new()
		outside.fov = 50.0
		outside.near = 0.01
		_world.add_child(outside)
		var points: Array = views[view]
		outside.look_at_from_position(points[0], points[1],
			Vector3.FORWARD if view == "top" else Vector3.UP)
		outside.current = true


## Lleva el componente al estado pedido por la misma API que usa el juego.
func _pose() -> void:
	var equip_time: float = float(_weapon.get(&"equip_time"))
	_weapon.set(&"_equip_left", equip_time * (1.0 - _progress) if _state == "equip" else 0.0)
	if _state == "reload":
		_weapon.set(&"_ammo", 0)
		_weapon.call(&"try_reload")
		_weapon.call(&"_process", float(_weapon.call(&"get_reload_time")) * _progress)
	elif _state == "grapple":
		_weapon.set(&"_grapple_blend", 1.0)
		var launcher: Node = _weapon.get(&"_launcher")
		if launcher != null:
			launcher.set(&"_grappling", true)
	# Quieto en esa pose: el componente sigue en el arbol y su propio _process
	# terminaria la recarga o el equipar antes de la foto.
	_weapon.set_process(false)
	_weapon.call(&"_tick_viewmodel", 0.0)
