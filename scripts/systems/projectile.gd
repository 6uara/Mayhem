class_name Projectile
extends Node3D
## Pooled, stepped projectile. Never a RigidBody3D - it integrates its own motion and
## raycasts the segment it travelled this frame so fast rounds cannot tunnel.

const MAX_LIFETIME: float = 5.0

@export var impact_scene: PackedScene

var _velocity: Vector3 = Vector3.ZERO
var _gravity: float = 0.0
var _damage: float = 0.0
var _falloff_start: float = 0.0
var _falloff_end: float = 0.0
var _falloff_min: float = 1.0
var _headshot_multiplier: float = 2.0
var _origin: Vector3 = Vector3.ZERO
var _shooter: Node = null
var _lifetime: float = 0.0
var _is_active: bool = false
## Trazadora: la bala ya pego, esto es lo que se ve viajar hasta ahi.
##
## No raycastea nada. El disparo se resolvio al apretar el gatillo, asi que
## preguntarle de nuevo a la fisica en cada frame es preguntar algo que ya esta
## contestado - y era el grueso del costo de disparar.
var _is_tracer: bool = false
var _tracer_target: Vector3 = Vector3.ZERO
var _tracer_normal: Vector3 = Vector3.UP
var _tracer_surface: SurfaceMaterialData
## Si la trazadora tiene que reventar algo al llegar, o solo desaparecer.
var _tracer_impacts: bool = false

@onready var _mesh: Node3D = $Mesh


## Arms the projectile. `direction` is expected normalized.
func launch(from: Vector3, direction: Vector3, data: WeaponData, shooter: Node,
		damage_override: float = -1.0) -> void:
	global_position = from
	_origin = from
	_velocity = direction * data.projectile_speed
	_gravity = data.projectile_gravity
	_damage = data.damage if damage_override < 0.0 else damage_override
	_falloff_start = data.falloff_start
	_falloff_end = data.falloff_end
	_falloff_min = data.falloff_min_multiplier
	_headshot_multiplier = data.headshot_multiplier
	_shooter = shooter
	_lifetime = 0.0
	_is_active = true
	if _mesh != null:
		_mesh.visible = true
	_face_travel()


func _physics_process(delta: float) -> void:
	if not _is_active:
		return
	if _is_tracer:
		_advance_tracer(delta)
		return

	_lifetime += delta
	if _lifetime >= MAX_LIFETIME:
		_expire()
		return

	if _gravity != 0.0:
		_velocity.y -= _gravity * delta

	var from: Vector3 = global_position
	var to: Vector3 = from + _velocity * delta
	var hit: Dictionary = _cast(from, to)
	if hit.is_empty():
		global_position = to
		_face_travel()
		return

	_resolve_hit(hit)


# Pool hooks

func _on_acquired() -> void:
	_is_active = false
	_lifetime = 0.0


func _on_released() -> void:
	_is_active = false
	_velocity = Vector3.ZERO
	_shooter = null
	# Pooleado: la proxima salida de esta bala puede ser una de verdad.
	_is_tracer = false
	_tracer_impacts = false
	_tracer_surface = null


## Lanza la parte visible de un disparo ya resuelto.
##
## `to` es donde pego de verdad, calculado en el momento del disparo. La
## trazadora solo tiene que llegar hasta ahi y reventar - el daño ya se aplico.
func launch_tracer(from: Vector3, to: Vector3, speed: float, normal: Vector3,
		surface: SurfaceMaterialData, spawn_impact: bool) -> void:
	global_position = from
	_origin = from
	_tracer_target = to
	_tracer_normal = normal
	_tracer_surface = surface
	_tracer_impacts = spawn_impact
	var offset: Vector3 = to - from
	_velocity = Vector3.ZERO
	if offset.length_squared() > 0.0001:
		_velocity = offset.normalized() * maxf(speed, 1.0)
	_gravity = 0.0
	_lifetime = 0.0
	_is_active = true
	_is_tracer = true
	if _mesh != null:
		_mesh.visible = true
	_face_travel()


## Un paso de trazadora: avanzar y mirar si ya llego. Sin consulta a la fisica.
func _advance_tracer(delta: float) -> void:
	_lifetime += delta
	var step: Vector3 = _velocity * delta
	var remaining: float = global_position.distance_to(_tracer_target)
	if _lifetime >= MAX_LIFETIME or remaining <= step.length() or remaining < 0.05:
		global_position = _tracer_target
		if _tracer_impacts:
			_spawn_impact(_tracer_target, _tracer_normal, null, _tracer_surface)
		_expire()
		return
	global_position += step


# Private

func _cast(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to,
		PhysicsLayers.WORLD | PhysicsLayers.HITBOX)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	if _shooter != null and _shooter is CollisionObject3D:
		query.exclude = [(_shooter as CollisionObject3D).get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)


func _resolve_hit(hit: Dictionary) -> void:
	var hit_position: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	var collider: Object = hit["collider"]

	global_position = hit_position

	var hitbox := collider as HitboxComponent
	if hitbox != null:
		var distance: float = _origin.distance_to(hit_position)
		var damage: float = _damage * _get_falloff(distance)
		# The weapon owns the headshot multiplier; the hitbox owns its own
		# per-enemy damage_multiplier and applies it in take_hit().
		if hitbox.is_headshot_zone:
			damage *= _headshot_multiplier
		# Not applied here any more: in coop the host owns every enemy's health,
		# and a client that damaged its own copy would watch an enemy it had
		# already killed keep walking. The replicator decides whether this
		# machine may resolve the hit or has to ask. Solo takes the same call and
		# resolves it on the spot.
		if EnemyReplicator.instance != null:
			EnemyReplicator.instance.report_hit(hitbox, damage, hit_position)
		else:
			hitbox.take_hit(damage, hit_position)
	_spawn_impact(hit_position, normal, collider)
	_expire()


func _get_falloff(distance: float) -> float:
	if distance <= _falloff_start or _falloff_end <= _falloff_start:
		return 1.0
	if distance >= _falloff_end:
		return _falloff_min
	return lerpf(1.0, _falloff_min, (distance - _falloff_start) / (_falloff_end - _falloff_start))


## `surface` viene ya resuelta cuando el que llama la sabe - la trazadora la
## recibe del disparo original, porque para cuando llega ya no tiene contra que
## preguntarla.
func _spawn_impact(hit_position: Vector3, normal: Vector3, collider: Object,
		surface: SurfaceMaterialData = null) -> void:
	if impact_scene == null:
		return
	var impact: Node = ObjectPool.acquire(impact_scene)
	if impact == null:
		return
	if impact.has_method(&"play_at"):
		var material: SurfaceMaterialData = surface
		if material == null:
			material = SurfaceMaterials.resolve(collider)
		impact.call(&"play_at", hit_position, normal, material)


func _face_travel() -> void:
	if _velocity.length_squared() < 0.001:
		return
	var direction: Vector3 = _velocity.normalized()
	# look_at() fails when the forward axis is parallel to the up vector.
	var up: Vector3 = Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.999 else Vector3.FORWARD
	look_at(global_position + direction, up)


func _expire() -> void:
	_is_active = false
	if _mesh != null:
		_mesh.visible = false
	ObjectPool.release(self)
