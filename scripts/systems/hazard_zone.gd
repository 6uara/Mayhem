class_name HazardZone
extends Area3D
## A damaging volume with an honest footprint.
##
## The floor decal is drawn at the **exact** damage radius - never larger, never
## smaller - and there is always a 0.6s warning before it can hurt anyone. A hazard
## that damages outside its own decal is a bug, not a difficulty setting.
##
## Used for arena traps and for the Elite's slam, which is why the radius and
## duration are arguments rather than constants.

signal expired()

@export var damage: float = 20.0
## Seconds between the damage ticks while something stands in it.
@export var tick_interval: float = 0.6
## How far above the pool's own floor a body may be and still count as standing in
## it. Acid on the ground must not reach someone on a platform overhead - the decal
## is the promise, and a promise that leaks upward through a floor is worse than no
## telegraph at all.
@export var damage_height: float = 2.2
## 0 = permanent arena trap. Above 0 = a temporary pool, like the Elite's slam.
@export var duration: float = 0.0
@export var radius: float = 3.0:
	set(value):
		radius = maxf(value, 0.1)
		_apply_radius()

@export var telegraph: TelegraphComponent
@export var decal_mesh: MeshInstance3D
@export var collision: CollisionShape3D
@export var warning_sound: AudioStream

## True once the warning has elapsed and it can actually damage.
var is_armed: bool = false

## Quién causó el charco, o `null` en una trampa del arena, que no es de nadie.
## Lo que muera adentro es de quien lo puso (PLAN_NEW_ENEMY_TYPES §2.4). Que sea
## el enemigo y no el charco importa: el charco vuelve al pool y el próximo lo
## reusa, el enemigo no.
var attacker: Node = null

var _time_left: float = 0.0
var _tick_timer: float = 0.0
var _bodies_inside: Array[Node3D] = []


func _ready() -> void:
	add_to_group(&"hazard")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_apply_radius()
	arm()


func _physics_process(delta: float) -> void:
	if not is_armed:
		return

	if duration > 0.0:
		_time_left -= delta
		if _time_left <= 0.0:
			_expire()
			return

	_tick_timer -= delta
	if _tick_timer > 0.0:
		return
	_tick_timer = tick_interval
	for body: Node3D in _bodies_inside:
		if is_instance_valid(body):
			_damage(body)


# Public API

## Starts the warning, then arms. Callers await nothing: the zone handles its own
## timing so every hazard in the game warns for exactly the same 0.6s.
func arm() -> void:
	is_armed = false
	_time_left = duration
	if telegraph != null:
		telegraph.set_blink_step(0.15)
		telegraph.state = TelegraphComponent.State.WARNING
	AudioPool.play_3d(warning_sound, global_position, AudioPool.BUS_WORLD,
		0.0, 1.0, AudioPool.Priority.TELEGRAPH)

	await get_tree().create_timer(Tokens.HAZARD_WARNING).timeout
	if not is_inside_tree():
		return
	is_armed = true
	_tick_timer = 0.0
	if telegraph != null:
		telegraph.state = TelegraphComponent.State.ACTIVE


## Reconfigures a pooled hazard - the Elite's slam uses this.
func setup(hazard_damage: float, hazard_radius: float, hazard_duration: float,
		hazard_attacker: Node = null) -> void:
	damage = hazard_damage
	radius = hazard_radius
	duration = hazard_duration
	attacker = hazard_attacker
	_bodies_inside.clear()
	arm()


# Private

## The decal, the collision shape and the damage radius are one number. Setting
## them separately is how a hazard ends up lying about where it hurts.
func _apply_radius() -> void:
	if collision != null and collision.shape is CylinderShape3D:
		# A sub-resource authored in a .tscn is shared by every instance of it unless
		# it says otherwise, so writing the radius here wrote it into the scene's own
		# shape - and the editor then saved that runtime value back to disk, shrinking
		# the authored hazard a little more each time. The scene marks this one
		# local_to_scene; this duplicate covers hazards built from code, which have no
		# scene to inherit that from.
		if not collision.shape.resource_local_to_scene:
			collision.shape = collision.shape.duplicate()
		var cylinder := collision.shape as CylinderShape3D
		cylinder.radius = radius
	if decal_mesh != null:
		decal_mesh.scale = Vector3(radius, 1.0, radius)


func _damage(body: Node3D) -> void:
	if not body.is_in_group(&"player") and not body.is_in_group(&"enemy"):
		return
	# Un charco con dueño no quema a los del dueño. Antes sí: el charco del Elite
	# lastimaba a la horda entera, que es el fuego amigo que §5.2 del plan reserva
	# **sólo** para la explosión del Bomber. Una trampa del arena no tiene dueño y
	# sigue quemando a todo el mundo, que es lo correcto para una trampa.
	if is_instance_valid(attacker) and not Factions.hostile(attacker, body):
		return
	if not _is_standing_in_it(body):
		return
	for child: Node in body.get_children():
		var health := child as HealthComponent
		if health != null:
			health.apply_damage(damage, attacker if is_instance_valid(attacker) else null)
			return


## A tall trigger volume catches anyone in the column of air above the pool. Being
## inside the volume is not the same as being in the acid: the feet have to be near
## the pool's own floor, with nothing solid in between.
func _is_standing_in_it(body: Node3D) -> bool:
	var height_above: float = body.global_position.y - global_position.y
	if height_above < -0.5 or height_above > damage_height:
		return false

	# Anything solid between the pool and the body means the body is standing on it.
	var from: Vector3 = body.global_position + Vector3.UP * 0.05
	var to := Vector3(from.x, global_position.y + 0.02, from.z)
	if from.y <= to.y:
		return true
	var query := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.WORLD)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _on_body_entered(body: Node3D) -> void:
	if not _bodies_inside.has(body):
		_bodies_inside.push_back(body)


func _on_body_exited(body: Node3D) -> void:
	_bodies_inside.erase(body)


func _expire() -> void:
	is_armed = false
	_bodies_inside.clear()
	expired.emit()
	if telegraph != null:
		telegraph.state = TelegraphComponent.State.IDLE
	# Pooled hazards go home; arena traps are placed by hand and stay.
	ObjectPool.release(self)
