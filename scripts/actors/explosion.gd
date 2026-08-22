class_name Explosion
extends Node3D
## El estallido del Bomber: un solo tick de daño en una esfera, y nada más.
##
## Es deliberadamente NO un HazardZone. Un hazard avisa 0.6s antes de armarse y
## después castiga a quien se queda parado; una explosión ya avisó - la espoleta
## del Bomber fue el aviso, y fue mucho más larga que 0.6s - y lo que hace es
## resolverse en el instante en que llega. Un charco con 0.6s de gracia después
## de que la bomba revienta no es una explosión, es un charco.
##
## Lo que sí hereda de HazardZone es la ley: el radio que lastima es exactamente
## el que se dibujó. El anillo que el Bomber arrastró durante toda la cuenta está
## autorado con `EnemyData.explosion_radius`, y esto usa ese mismo número.
##
## Golpea a todo el mundo, jugador y horda por igual. Ese es el único fuego amigo
## que existe dentro de la horda (ver PLAN_NEW_ENEMY_TYPES §5.2), y es la mitad
## que hace que matar un Bomber al lado de un grupo sea una jugada.

signal detonated(hit_count: int)

## Cuánto dura el destello antes de volver al pool. No hace daño en ese rato: el
## daño ya se aplicó, esto es sólo lo que se ve.
@export var flash_time: float = 0.35
@export var flash_mesh: MeshInstance3D

var _time_left: float = 0.0
var _material: StandardMaterial3D


func _ready() -> void:
	_build_material()


func _process(delta: float) -> void:
	if _time_left <= 0.0:
		return
	_time_left -= delta
	# La bola crece y se apaga. Crecer hasta el radio real y no más es lo que
	# hace que el jugador aprenda de una explosión cuánto abarca la siguiente.
	var progress: float = clampf(1.0 - _time_left / maxf(flash_time, 0.01), 0.0, 1.0)
	if flash_mesh != null:
		flash_mesh.scale = Vector3.ONE * lerpf(0.25, 1.0, progress)
	if _material != null:
		_material.albedo_color.a = 1.0 - progress
	if _time_left <= 0.0:
		ObjectPool.release(self)


# Public API

## Revienta acá, ahora. Devuelve a cuántos alcanzó.
##
## `source` es quien la causó y queda excluido - un Bomber no se mata a sí mismo
## dos veces, ya está muerto.
##
## `attacker` es de quién es lo que la explosión mate, y **no** es lo mismo que
## `source`: el que revienta es el Bomber, pero el dueño de la cadena es el que
## voló al Bomber (PLAN_NEW_ENEMY_TYPES §5.4). Esa distinción es toda la jugada -
## si la explosión se atribuyera a sí misma, elegir dónde matarlo no pagaría nada
## y el arquetipo volvería a ser un accidente. `null` deja la muerte sin dueño,
## que es lo correcto para un Bomber que reventó solo sin que nadie lo tocara.
func detonate(radius: float, damage: float, sound: AudioStream = null,
		source: Node3D = null, attacker: Node = null) -> int:
	radius = maxf(radius, 0.1)
	if flash_mesh != null:
		flash_mesh.mesh = _flash_mesh_for(radius)
		flash_mesh.scale = Vector3.ONE * 0.25
	_time_left = flash_time
	if _material != null:
		_material.albedo_color.a = 1.0
	AudioPool.play_3d(sound, global_position, AudioPool.BUS_ENEMIES)

	var hits: int = 0
	for body: Node3D in _victims(radius):
		if body == source or not is_instance_valid(body):
			continue
		if not _has_line_to(body):
			# Una explosión no dobla esquinas. Sin esto la bomba mata a través
			# de una pared, que es daño sin nada en pantalla que lo explique -
			# exactamente la falla que el raycast de Enemy.deal_melee_damage()
			# arregló para el cuerpo a cuerpo.
			continue
		var health: HealthComponent = _find_health(body)
		if health == null:
			continue
		health.apply_damage(damage, attacker if is_instance_valid(attacker) else null)
		hits += 1
	detonated.emit(hits)
	return hits


func _on_acquired() -> void:
	_time_left = 0.0
	if flash_mesh != null:
		flash_mesh.scale = Vector3.ONE * 0.25
	_build_material()


func _on_released() -> void:
	_time_left = 0.0


# Private

## Quién está adentro del radio, preguntándoselo al servidor de física.
##
## Deliberadamente sin nombrar a `Enemy`. La primera versión recorría
## `Enemy.get_active_enemies()` y `Players`, y eso arma una dependencia circular:
## `enemy.gd` ya nombra a `Explosion` para lanzar el estallido. GDScript a veces
## resuelve ese ciclo y a veces no, según el orden en que compile - y cuando no,
## `enemy.gd` entero deja de existir como clase y la escena del enemigo se
## instancia como un `CharacterBody3D` pelado. No falla donde está el error.
##
## Una consulta de forma además mide mejor: usa el colisionador real de cada
## cuerpo en vez de adivinarle el centro a partir de su altura. El filtro por
## grupo es el mismo que usa `HazardZone._damage()`, y es donde va a ir la
## pregunta por facción cuando lleguen los Gladiadores (§5.2 del plan).
func _victims(radius: float) -> Array[Node3D]:
	var found: Array[Node3D] = []
	var world: World3D = get_world_3d()
	if world == null:
		return found

	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis(), global_position)
	# Todas las capas con gente adentro: una explosión no distingue bandos, y ese
	# es justamente su lugar en la matriz de §5.2 - el único fuego amigo que hay.
	query.collision_mask = PhysicsLayers.PLAYER | PhysicsLayers.ENEMY \
		| PhysicsLayers.GLADIATOR
	# Los cuerpos, no las areas: los hitboxes son Area3D y devolverian el mismo
	# enemigo dos veces, una por el cuerpo y otra por cada caja de impacto.
	query.collide_with_areas = false
	query.collide_with_bodies = true

	for result: Dictionary in world.direct_space_state.intersect_shape(query, 32):
		var body := result["collider"] as Node3D
		if body == null or found.has(body):
			continue
		if not body.is_in_group(&"player") and not body.is_in_group(&"enemy"):
			continue
		found.append(body)
	return found


func _has_line_to(body: Node3D) -> bool:
	var world: World3D = get_world_3d()
	if world == null:
		return true
	# Al pecho y no a los pies: un cuerpo parado en una rampa tiene el origen
	# tapado por la rampa misma, y el rayo se comería el impacto.
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.4, body.global_position + Vector3.UP * 0.8,
		PhysicsLayers.WORLD)
	return world.direct_space_state.intersect_ray(query).is_empty()


func _flash_mesh_for(radius: float) -> Mesh:
	var sphere := flash_mesh.mesh as SphereMesh
	if sphere == null:
		sphere = SphereMesh.new()
	else:
		# Pooleada: la malla viene del ocupante anterior, que tenía otro radio.
		sphere = sphere.duplicate() as SphereMesh
	sphere.radius = radius
	sphere.height = radius * 2.0
	return sphere


func _build_material() -> void:
	if flash_mesh == null:
		return
	_material = StandardMaterial3D.new()
	_material.albedo_color = Tokens.HAZARD
	_material.emission_enabled = true
	_material.emission = Tokens.HAZARD
	_material.emission_energy_multiplier = 3.0
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mesh.material_override = _material


func _find_health(node: Node) -> HealthComponent:
	for child: Node in node.get_children():
		var component := child as HealthComponent
		if component != null:
			return component
	return null
