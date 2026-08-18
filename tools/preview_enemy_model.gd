extends SceneTree
## Renderiza un arquetipo a PNG para revisar escala, apoyo y orientacion.
##
##   godot --path . -s res://tools/preview_enemy_model.gd -- rusher
##
## Sale a res://enemy_preview.png. Camara puesta donde estaria el jugador al que
## el enemigo esta encarando (un cuerpo avanza hacia -Z en Godot), asi que si en
## la imagen no le ves la cara, le falta model_yaw_degrees.
##
## La regla roja mide un metro exacto: es la referencia para model_scale.
## El enemigo queda con la fisica apagada porque el piso de esta escena no tiene
## colision - sin eso se cae del mundo antes de que se saque la foto.

const OUTPUT: String = "res://enemy_preview.png"

var _frames: int = 0
var _enemy: Node3D
var _archetype: String = "rusher"


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		_archetype = argument

	var world := Node3D.new()
	get_root().add_child(world)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -40.0, 0.0)
	light.light_energy = 1.4
	world.add_child(light)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.1, 0.11, 0.13)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	environment.ambient_light_energy = 0.6
	var holder := WorldEnvironment.new()
	holder.environment = environment
	world.add_child(holder)

	world.add_child(_slab(Vector3(8.0, 0.0, 8.0), Vector3.ZERO, Color(0.18, 0.19, 0.22)))
	world.add_child(_slab(Vector3(0.05, 1.0, 0.05), Vector3(1.2, 0.5, 0.0),
		Color(0.9, 0.2, 0.2)))

	_enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	world.add_child(_enemy)

	var camera := Camera3D.new()
	var eye := Vector3(0.0, 0.9, -2.6)
	camera.look_at_from_position(eye, Vector3(0.0, 0.55, 0.0), Vector3.UP)
	world.add_child(camera)
	camera.current = true


func _process(_delta: float) -> bool:
	_frames += 1
	# setup() reads global transforms, so it has to wait until the body is
	# actually in the tree - a frame after add_child, not during _initialize.
	if _frames == 2:
		var path: String = "res://data/enemies/%s.tres" % _archetype
		var data: EnemyData = load(path)
		if data == null:
			print("no existe ", path)
			return true
		_enemy.setup(data, Vector3.ZERO)
		_enemy.set_physics_process(false)
		return false
	if _frames < 12:
		return false
	get_root().get_texture().get_image().save_png(OUTPUT)
	print("guardado ", OUTPUT, " (", _archetype, ")")
	return true


func _slab(size: Vector3, position: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	if is_zero_approx(size.y):
		var plane := PlaneMesh.new()
		plane.size = Vector2(size.x, size.z)
		node.mesh = plane
	else:
		var box := BoxMesh.new()
		box.size = size
		node.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	node.material_override = material
	node.position = position
	return node
