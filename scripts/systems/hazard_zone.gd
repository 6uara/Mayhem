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
	AudioPool.play_3d(warning_sound, global_position, AudioPool.BUS_WORLD)

	await get_tree().create_timer(Tokens.HAZARD_WARNING).timeout
	if not is_inside_tree():
		return
	is_armed = true
	_tick_timer = 0.0
	if telegraph != null:
		telegraph.state = TelegraphComponent.State.ACTIVE


## Reconfigures a pooled hazard - the Elite's slam uses this.
func setup(hazard_damage: float, hazard_radius: float, hazard_duration: float) -> void:
	damage = hazard_damage
	radius = hazard_radius
	duration = hazard_duration
	_bodies_inside.clear()
	arm()


# Private

## The decal, the collision shape and the damage radius are one number. Setting
## them separately is how a hazard ends up lying about where it hurts.
func _apply_radius() -> void:
	if collision != null and collision.shape is CylinderShape3D:
		var cylinder := collision.shape as CylinderShape3D
		cylinder.radius = radius
	if decal_mesh != null:
		decal_mesh.scale = Vector3(radius, 1.0, radius)


func _damage(body: Node3D) -> void:
	if not body.is_in_group(&"player") and not body.is_in_group(&"enemy"):
		return
	for child: Node in body.get_children():
		var health := child as HealthComponent
		if health != null:
			health.apply_damage(damage)
			return


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
