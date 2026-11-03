class_name ShaderWarmup
extends Node3D
## Dibuja una vez, detras de la transicion de carga, todo lo que la pelea va a
## mostrar por primera vez: cada arquetipo, la explosion, los impactos, los
## charcos. Asi el tiron de compilar un pipeline cae en la pantalla negra y no
## en el primer disparo ni en la primera muerte.
##
## Godot 4.7 compila con ubershaders en segundo plano y la mayoria de esos
## tirones ya no se notan en una GPU dedicada; en la integrada de referencia
## (680M, ESTADO §5) todavia aparece la primera explosion. PoolPrewarmer ya
## instancia lo pooleado, pero lo deja invisible, y lo que no se dibuja no
## compila nada.
##
## Lo dibujado es una copia **visual**: se le sacan los scripts antes de entrar al
## arbol, asi que una explosion de aca no hace daño ni suena, y un efecto que se
## devuelve solo al pool no se devuelve a ningun lado. Queda delante de la camara,
## a unos metros, el tiempo de `ShaderWarmupList.frames` y se borra.
##
## La corre GameManager, con la pantalla tapada, entre que la escena nueva esta
## puesta y la transicion se abre (`run()`). Sin GameManager (una escena de prueba)
## no corre: no hay nada que tapar.

const GROUP: StringName = &"shader_warmup"
const ENEMY_DIR: String = "res://data/enemies"
## Delante de la camara, donde entra en el frustum y no en el plano cercano.
const DISTANCE: float = 4.0
## Separacion entre copias, para que no se tapen entre si del todo. Tapadas igual
## compilan; separadas, el que mira un frame suelto entiende que es.
const SPACING: float = 0.6

@export var list: ShaderWarmupList


func _ready() -> void:
	add_to_group(GROUP)


## Dibuja todo `list.frames` frames y lo borra. Devuelve cuantas cosas dibujo.
func run() -> int:
	# Sin render (la suite, CI) no hay nada que compilar, y esperar un
	# `frame_post_draw` que el servidor de render nulo puede no emitir colgaria la
	# carga de la partida.
	if list == null or DisplayServer.get_name() == "headless":
		return 0
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return 0
	var copies: Array[Node3D] = build_copies()
	if copies.is_empty():
		return 0
	var holder := Node3D.new()
	holder.name = "WarmupHolder"
	add_child(holder)
	holder.global_transform = camera.global_transform.translated_local(
		Vector3(0.0, 0.0, -DISTANCE))
	for index: int in copies.size():
		var copy: Node3D = copies[index]
		holder.add_child(copy)
		var column: int = index % 5 - 2
		var row: int = index / 5 - 1
		copy.position = Vector3(float(column) * SPACING, float(row) * SPACING, 0.0)
		_start_particles(copy)
	for _frame: int in list.frames:
		await RenderingServer.frame_post_draw
	holder.queue_free()
	return copies.size()


## Las copias visuales, todavia fuera del arbol. Publico para los tests.
func build_copies() -> Array[Node3D]:
	var copies: Array[Node3D] = []
	if list == null:
		return copies
	var sources: Array[PackedScene] = list.scenes.duplicate()
	if list.include_enemy_models:
		sources.append_array(_enemy_models())
	for scene: PackedScene in sources:
		if scene == null:
			continue
		var instance: Node = scene.instantiate()
		var copy := instance as Node3D
		if copy == null:
			instance.free()
			continue
		strip_scripts(copy)
		copies.append(copy)
	return copies


## Saca el script de `node` y de todo lo que cuelga de el: queda la malla, el
## material y las particulas, sin comportamiento. Y lo deja visible: varios
## efectos arrancan apagados y se prenden por script (el fogonazo, el aro del
## gadget), y lo apagado no compila.
static func strip_scripts(node: Node) -> void:
	for child: Node in node.get_children():
		strip_scripts(child)
	if node.get_script() != null:
		node.set_script(null)
	if node is Node3D:
		(node as Node3D).visible = true
	# Una pared temporal a cuatro metros de la camara empujaria al jugador recien
	# puesto en la arena: las copias no chocan con nada.
	if node is CollisionObject3D:
		var body := node as CollisionObject3D
		body.collision_layer = 0
		body.collision_mask = 0


static func _start_particles(node: Node) -> void:
	if node is GPUParticles3D:
		var particles := node as GPUParticles3D
		particles.one_shot = false
		particles.emitting = true
	elif node is CPUParticles3D:
		var cpu := node as CPUParticles3D
		cpu.one_shot = false
		cpu.emitting = true
	for child: Node in node.get_children():
		_start_particles(child)


static func _enemy_models() -> Array[PackedScene]:
	var models: Array[PackedScene] = []
	for file_name: String in DirAccess.get_files_at(ENEMY_DIR):
		var path: String = "%s/%s" % [ENEMY_DIR, file_name.trim_suffix(".remap")]
		if not path.ends_with(".tres"):
			continue
		var data := load(path) as EnemyData
		if data != null and data.model_scene != null and not models.has(data.model_scene):
			models.append(data.model_scene)
	return models
