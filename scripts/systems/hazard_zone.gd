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
## Cuanto se mete el contorno hacia adentro del radio, como fraccion. Cero es un
## circulo, que es lo que sigue usando el snare. Con mas, el charco tiene
## lobulos y deja de ser un disco - y el dano sigue ese mismo contorno, no el
## circulo: `radius` pasa a ser lo mas lejos que llega, no por donde pasa el
## borde en todos lados.
@export_range(0.0, 0.5, 0.01) var shape_irregularity: float = 0.0

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

## Ya vencio y se esta secando: no lastima ni cuenta como charco vivo, pero
## todavia se ve.
var is_evaporating: bool = false

var _time_left: float = 0.0
## Esparcirse y secarse. Se guarda para matarlo: un charco que vuelve al pool y
## se reusa no puede heredar el secado del anterior, que lo soltaria a mitad de
## su vida nueva.
var _look_tween: Tween
## El contorno: tres armonicos en angulo con fases al azar por charco. Lo mismo
## evalua `acid_pool.gdshader`; si no coinciden, el dibujo miente.
var _shape_phase: Vector3 = Vector3.ZERO
var _shape_min: float = -1.0
var _shape_span: float = 2.0

## Peso de los armonicos 2, 3 y 5. El 2 estira el charco hacia un lado, el 3 y
## el 5 le hacen los lobulos. Sin armonico 1: desplazaria el charco del centro.
const SHAPE_WEIGHTS: Vector3 = Vector3(0.5, 0.3, 0.2)
const SHAPE_SAMPLES: int = 96
var _tick_timer: float = 0.0
var _bodies_inside: Array[Node3D] = []


func _ready() -> void:
	add_to_group(&"hazard")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_apply_radius()
	# A trap placed in the level arms itself. One built by ObjectPool is armed by
	# setup() a moment later, where it lands: arming it here too played the
	# warning at the arena origin, where the pool instantiates it.
	if not has_meta(ObjectPool.POOLED_META):
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
	is_evaporating = false
	_time_left = duration
	if telegraph != null:
		telegraph.set_blink_step(0.15)
		telegraph.state = TelegraphComponent.State.WARNING
	_roll_shape()
	_spread_in()
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


## El charco se esparce desde el centro mientras avisa. No lastima durante el
## aviso, asi que crecer no miente sobre nada, y es movimiento: avisa tambien a
## quien no distingue el verde del parpadeo.
func _spread_in() -> void:
	_kill_look_tween()
	_set_look(0.15, 0.0)
	if not is_inside_tree():
		_set_look(1.0, 0.0)
		return
	_look_tween = create_tween()
	_look_tween.tween_method(func(value: float) -> void: _set_look(value, 0.0),
		0.15, 1.0, Tokens.HAZARD_WARNING).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Fraccion del radio a la que llega el borde en `angle` (radianes, en el plano
## XZ local, desde +X hacia +Z). Entre 1 - shape_irregularity y 1.
func reach_at(angle: float) -> float:
	if shape_irregularity <= 0.0:
		return 1.0
	var s: float = _shape_wave(angle)
	return 1.0 - shape_irregularity * clampf((s - _shape_min) / _shape_span, 0.0, 1.0)


func _shape_wave(angle: float) -> float:
	return SHAPE_WEIGHTS.x * sin(2.0 * angle + _shape_phase.x) \
		+ SHAPE_WEIGHTS.y * sin(3.0 * angle + _shape_phase.y) \
		+ SHAPE_WEIGHTS.z * sin(5.0 * angle + _shape_phase.z)


## Contorno nuevo en cada aparicion, normalizado para que en algun angulo toque
## el radio: el charco llega exactamente hasta `radius`, ni mas ni menos.
func _roll_shape() -> void:
	_shape_phase = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	var low: float = INF
	var high: float = -INF
	for i: int in SHAPE_SAMPLES:
		var s: float = _shape_wave(TAU * float(i) / float(SHAPE_SAMPLES))
		low = minf(low, s)
		high = maxf(high, s)
	_shape_min = low
	_shape_span = maxf(high - low, 0.001)
	var material := decal_mesh.material_override as ShaderMaterial if decal_mesh != null else null
	if material == null:
		return
	material.set_shader_parameter(&"shape_inset", shape_irregularity)
	material.set_shader_parameter(&"shape_phase", _shape_phase)
	material.set_shader_parameter(&"shape_weights", SHAPE_WEIGHTS)
	material.set_shader_parameter(&"shape_min", _shape_min)
	material.set_shader_parameter(&"shape_span", _shape_span)


func _set_look(spread: float, evaporate: float) -> void:
	var material := decal_mesh.material_override as ShaderMaterial if decal_mesh != null else null
	if material == null:
		return
	material.set_shader_parameter(&"spread", spread)
	material.set_shader_parameter(&"evaporate", evaporate)


func _kill_look_tween() -> void:
	if _look_tween != null and _look_tween.is_valid():
		_look_tween.kill()
	_look_tween = null


func _on_released() -> void:
	_kill_look_tween()
	is_evaporating = false


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
	# El volumen es el cilindro del radio entero; el charco, no. Lo que queda
	# entre un lobulo y el cilindro es piso seco, y pisarlo no quema.
	var local: Vector3 = global_transform.affine_inverse() * body.global_position
	var flat := Vector2(local.x, local.z)
	if flat.length() > radius * reach_at(flat.angle()):
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
	# Se seca antes de volver al pool. Ya no lastima desde la linea de arriba:
	# lo que queda es solo la imagen, y dura menos que STATE_SETTLE_MAX.
	is_evaporating = true
	_kill_look_tween()
	_look_tween = create_tween()
	_look_tween.tween_method(func(value: float) -> void: _set_look(1.0, value),
		0.0, 1.0, Tokens.HAZARD_EVAPORATE)
	# Pooled hazards go home; arena traps are placed by hand and stay.
	_look_tween.tween_callback(ObjectPool.release.bind(self))
