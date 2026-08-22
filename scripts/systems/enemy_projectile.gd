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
## A copy of someone else's shot, flying on a client so its player can see and
## dodge it. It travels and splashes exactly like the real one and takes nobody's
## hit points: the host already resolved that against its own copy, and applying
## it here as well would charge the player twice for one bullet.
var _is_cosmetic: bool = false

@onready var _mesh: Node3D = $Mesh


func launch(from: Vector3, direction: Vector3, damage: float, speed: float,
		shooter: Node) -> void:
	global_position = from
	_velocity = direction * speed
	_damage = damage
	_shooter = shooter
	_lifetime = 0.0
	_is_active = true
	_is_cosmetic = false
	if _mesh != null:
		_mesh.visible = true


## The client-side twin of launch(). `shooter` is the local puppet of the enemy
## that fired, which is what keeps the shot from starting inside its own body.
func launch_cosmetic(from: Vector3, direction: Vector3, speed: float,
		shooter: Node) -> void:
	launch(from, direction, 0.0, speed, shooter)
	_is_cosmetic = true


func _physics_process(delta: float) -> void:
	if not _is_active:
		return
	_lifetime += delta
	if _lifetime >= MAX_LIFETIME:
		_expire()
		return

	var from: Vector3 = global_position
	var to: Vector3 = from + _velocity * delta
	# Las capas de lo que este tirador puede lastimar, y no `PLAYER` cableado. Era
	# el primero de los dos filtros que hacían imposible que un proyectil enemigo
	# tocara a un enemigo (PLAN_NEW_ENEMY_TYPES §2.2). Para la horda esto da
	# `PLAYER | GLADIATOR`, y como no hay ningún cuerpo en `GLADIATOR` todavía, la
	# bala vuela exactamente igual que antes.
	var query := PhysicsRayQueryParameters3D.create(from, to,
		PhysicsLayers.WORLD | Factions.hostile_mask(Factions.of(_shooter)))
	if _shooter != null and _shooter is CollisionObject3D:
		query.exclude = [(_shooter as CollisionObject3D).get_rid()]
	var hit: Dictionary = _shooter.get_world_3d().direct_space_state.intersect_ray(query) \
		if _shooter != null else {}

	if hit.is_empty():
		global_position = to
		return

	global_position = hit["position"]
	# El segundo filtro, que era `is_in_group(&"player")`: ahora pregunta por bando
	# en vez de preguntar por el jugador. Sin esto la máscara de arriba dejaría
	# pasar la bala hasta el cuerpo y el daño se caería igual, un metro después.
	var victim := hit["collider"] as Node
	if not _is_cosmetic and Factions.hostile(_shooter, victim):
		var health: HealthComponent = _find_health(victim)
		if health != null:
			health.apply_damage(_damage, _shooter)
	_spawn_impact(hit["position"], hit["normal"], hit["collider"])
	_expire()


func _on_acquired() -> void:
	_is_active = false
	_lifetime = 0.0


func _on_released() -> void:
	_is_active = false
	_velocity = Vector3.ZERO
	_shooter = null
	# Pooled: a round that came back from a cosmetic flight must not stay
	# harmless when the host reuses it for a real one.
	_is_cosmetic = false


func _spawn_impact(hit_position: Vector3, normal: Vector3, collider: Object) -> void:
	if impact_scene == null:
		return
	var impact: Node = ObjectPool.acquire(impact_scene)
	if impact != null and impact.has_method(&"play_at"):
		impact.call(&"play_at", hit_position, normal, SurfaceMaterials.resolve(collider))


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
