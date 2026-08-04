class_name EnemyProjectile
extends Node3D
## Pooled enemy projectile. Slower and larger than player rounds on purpose - it must
## be readable and dodgeable, which is what makes ranged attacks a movement problem
## rather than an unavoidable tax.

const MAX_LIFETIME: float = 6.0

@export var impact_scene: PackedScene

var _velocity: Vector3 = Vector3.ZERO
var _damage: float = 0.0
var _shooter: Node = null
var _lifetime: float = 0.0
var _is_active: bool = false

@onready var _mesh: Node3D = $Mesh


func launch(from: Vector3, direction: Vector3, damage: float, speed: float,
		shooter: Node) -> void:
	global_position = from
	_velocity = direction * speed
	_damage = damage
	_shooter = shooter
	_lifetime = 0.0
	_is_active = true
	if _mesh != null:
		_mesh.visible = true


func _physics_process(delta: float) -> void:
	if not _is_active:
		return
	_lifetime += delta
	if _lifetime >= MAX_LIFETIME:
		_expire()
		return

	var from: Vector3 = global_position
	var to: Vector3 = from + _velocity * delta
	var query := PhysicsRayQueryParameters3D.create(from, to,
		PhysicsLayers.WORLD | PhysicsLayers.PLAYER)
	if _shooter != null and _shooter is CollisionObject3D:
		query.exclude = [(_shooter as CollisionObject3D).get_rid()]
	var hit: Dictionary = _shooter.get_world_3d().direct_space_state.intersect_ray(query) \
		if _shooter != null else {}

	if hit.is_empty():
		global_position = to
		return

	global_position = hit["position"]
	var player := hit["collider"] as Node
	if player != null and player.is_in_group(&"player"):
		var health: HealthComponent = _find_health(player)
		if health != null:
			health.apply_damage(_damage)
	_spawn_impact(hit["position"], hit["normal"])
	_expire()


func _on_acquired() -> void:
	_is_active = false
	_lifetime = 0.0


func _on_released() -> void:
	_is_active = false
	_velocity = Vector3.ZERO
	_shooter = null


func _spawn_impact(hit_position: Vector3, normal: Vector3) -> void:
	if impact_scene == null:
		return
	var impact: Node = ObjectPool.acquire(impact_scene)
	if impact != null and impact.has_method(&"play_at"):
		impact.call(&"play_at", hit_position, normal, false)


func _expire() -> void:
	_is_active = false
	if _mesh != null:
		_mesh.visible = false
	ObjectPool.release(self)


func _find_health(node: Node) -> HealthComponent:
	for child: Node in node.get_children():
		var component := child as HealthComponent
		if component != null:
			return component
	return null
