extends Node
## Saca una foto del charco de acido y del piso que arde uno al lado del otro,
## armados y a la altura de los ojos. Para comparar que se lean distintos sin
## tener que jugar hasta que salga Scorched Earth y un Flask en la misma oleada.
##
##   godot --path . --resolution 1600x900 tools/capture_hazards.tscn -- ruta.png
##
## Con render de verdad, no --headless (ver capture_menu.gd).

const ACID: PackedScene = preload("res://scenes/arena/hazard_zone.tscn")
const FIRE: PackedScene = preload("res://scenes/arena/fire_pool.tscn")


func _ready() -> void:
	var target: String = "user://hazards.png"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		target = args[0]

	_build_stage()
	for entry: Array in [[ACID, -3.2], [FIRE, 3.2]]:
		var zone := (entry[0] as PackedScene).instantiate() as HazardZone
		add_child(zone)
		zone.global_position = Vector3(float(entry[1]), 0.0, 0.0)
		zone.setup(10.0, 2.5, 0.0)

	# Armado y con las llamas ya llenas: el aviso dura 0.6s y una llama vive 0.8s.
	await get_tree().create_timer(1.8).timeout
	await RenderingServer.frame_post_draw
	_save(target)
	get_tree().quit()


func _build_stage() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Tokens.VOID
	environment.ambient_light_color = Color(0.35, 0.37, 0.42)
	environment.ambient_light_energy = 0.6
	environment.glow_enabled = true
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	sun.light_energy = 0.5
	add_child(sun)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.32, 0.33, 0.36)
	material.roughness = 0.9
	plane.material = material
	floor_mesh.mesh = plane
	add_child(floor_mesh)

	var camera := Camera3D.new()
	camera.fov = 70.0
	add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 2.2, 7.5), Vector3(0.0, 0.3, 0.0))


func _save(path: String) -> void:
	var shot: Image = get_viewport().get_texture().get_image()
	var error: int = shot.save_png(path)
	print("captura: %s  %dx%d  error=%d" % [
		ProjectSettings.globalize_path(path), shot.get_width(), shot.get_height(), error])
