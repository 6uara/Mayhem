extends SceneTree
## Renderiza un arquetipo a PNG para revisar escala, apoyo y orientacion.
##
##   godot --path . -s res://tools/preview_enemy_model.gd -- rusher
##   godot --path . -s res://tools/preview_enemy_model.gd -- rusher walk
##
## Sale a user://enemy_preview.png (la ruta absoluta se imprime). Camara puesta donde estaria el jugador al que
## el enemigo esta encarando (un cuerpo avanza hacia -Z en Godot), asi que si en
## la imagen no le ves la cara, le falta model_yaw_degrees.
##
## Con "walk" pone cuatro copias en fila, cada una un cuarto de ciclo mas
## adelante que la anterior: la tira se lee como los cuadros de una caminata.
##
## OJO: esto corre con ventana (sin --headless, hace falta para renderizar), y en
## esa pasada Godot reescanea el proyecto y puede re-serializar .tscn/.tres -
## agregando uid= y, peor, borrando toda propiedad que sea igual a su default.
## Ya se llevo puesto un prewarm_count del EnemySpawner una vez. Mira git status
## despues de usar esto y revert lo que no hayas tocado vos.
##
## La regla roja mide un metro exacto: es la referencia para model_scale.
## El enemigo queda con la fisica apagada porque el piso de esta escena no tiene
## colision - sin eso se cae del mundo antes de que se saque la foto.

## Fuera del proyecto a proposito: un PNG dentro de res:// se lo importa Godot y
## te deja un .import al lado, y esto es una foto de trabajo, no un asset.
const OUTPUT: String = "user://enemy_preview.png"

var _frames: int = 0
var _enemies: Array[Node3D] = []
var _archetype: String = "rusher"
var _walking: bool = false
## Mirar la caminata de frente, que es como la ve el jugador cuando lo cargan.
var _from_front: bool = false
## Imprimir la altura real del punto mas bajo del modelo en vez de sacar la foto.
var _measuring: bool = false


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "walk":
			_walking = true
			continue
		if argument == "front":
			_from_front = true
			continue
		if argument == "measure":
			_measuring = true
			continue
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

	var count: int = 4 if _walking else 1
	for i: int in count:
		var enemy: Node3D = load("res://scenes/enemies/enemy.tscn").instantiate()
		world.add_child(enemy)
		enemy.position = Vector3(float(i) * 1.5 - (float(count) - 1.0) * 0.75, 0.0, 0.0)
		if _walking and not _from_front:
			# De perfil: el swing va hacia el -Z del cuerpo, y de frente eso pasa
			# por encima de la camara. Girados, la pata que adelanta se lee.
			enemy.rotation.y = PI * 0.5
		_enemies.append(enemy)

	var camera := Camera3D.new()
	# Los cuatro cuadros se miran de costado: la pata que adelanta es lo que hay
	# que leer, y de frente no se ve.
	var eye := Vector3(0.0, 1.0, -4.2) if _walking else Vector3(0.0, 0.9, -2.6)
	camera.look_at_from_position(eye, Vector3(0.0, 0.5, 0.0), Vector3.UP)
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
		for enemy: Node3D in _enemies:
			enemy.setup(data, enemy.position)
			enemy.set_physics_process(false)
		return false
	# Posar y sacar la foto no pueden pasar en el mismo frame: los
	# BoneAttachment3D copian la pose del hueso recien en el proceso del
	# esqueleto, asi que una captura inmediata muestra el modelo en reposo.
	if _frames == 4 and _walking:
		_pose_the_walk()
		return false
	if _frames < 14:
		return false
	if _measuring:
		_measure_ground_clearance()
		return true
	get_root().get_texture().get_image().save_png(OUTPUT)
	print("guardado ", ProjectSettings.globalize_path(OUTPUT), " (", _archetype, ")")
	return true


## Cada copia queda un cuarto de ciclo mas adelante. Se le miente la velocidad al
## componente y se lo hace correr a mano: la fisica esta apagada, asi que nadie
## se mueve de su lugar y las cuatro poses quedan quietas para la foto.
func _pose_the_walk() -> void:
	for i: int in _enemies.size():
		var enemy: Node3D = _enemies[i]
		var gait: LeggedGait = null
		for child: Node in enemy.get_children():
			var found := child as LeggedGait
			if found != null:
				gait = found
		if gait == null:
			print("sin gait: el modelo no tiene patas que caminen")
			return
		if i == 0:
			print("huesos tomados: ", gait._amplitude.size(),
				"  rodillas: ", gait._is_knee.values().count(true),
				"  amp_rodilla=", gait.knee_degrees)
		enemy.velocity = Vector3(0.0, 0.0, -7.2)
		# 1/60 por paso, las veces que haga falta para llegar a esta fase.
		var steps: int = 12 + i * 9
		for _step: int in steps:
			gait._physics_process(1.0 / 60.0)


## Vertice mas bajo del modelo, no la esquina de su caja: un AABB es una caja
## alrededor de la pieza y su piso puede quedar muy por debajo del pie real, que
## es como el bot termino flotando la primera vez.
func _measure_ground_clearance() -> void:
	var lowest: float = INF
	var owner_name: String = ""
	for mesh: MeshInstance3D in _model_meshes(_enemies[0]):
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var to_world: Transform3D = mesh.global_transform
		for vertex: Vector3 in mesh.mesh.get_faces():
			var y: float = (to_world * vertex).y
			if y < lowest:
				lowest = y
				owner_name = mesh.name
	print("punto mas bajo: y=", snappedf(lowest, 0.001), "  en ", owner_name)
	print("corregir model_offset.y en ", snappedf(-lowest, 0.001))


func _model_meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	var mesh := node as MeshInstance3D
	# La capsula gris esta oculta pero sigue en el arbol; no cuenta como apoyo.
	if mesh != null and mesh.name != "Mesh" and mesh.name != "Halo" and mesh.name != "Tether":
		found.append(mesh)
	for child: Node in node.get_children():
		found.append_array(_model_meshes(child))
	return found


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
