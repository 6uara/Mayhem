class_name RecoilVisualizer
extends Node3D
## Phase 1 deliverable, not a nice-to-have: fires a full magazine at a wall and draws
## the resulting pattern, so recoil can be authored and verified visually.
##
## Dev builds only. Toggle with F1, fire the test burst with F2.

const RAY_LENGTH: float = 100.0
const POINT_SIZE: float = 0.06

@export var weapon: WeaponComponent
@export var aim_node: Node3D
## Distance at which the pattern is projected, matching the range's pattern wall.
@export var wall_distance: float = 15.0

var _is_enabled: bool = false
var _points: PackedVector3Array = PackedVector3Array()

@onready var _multimesh: MultiMeshInstance3D = $Points


func _ready() -> void:
	if not _is_dev_build():
		queue_free()
		return
	_bind_weapon.call_deferred()
	visible = false


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F1:
		_set_enabled(not _is_enabled)
	elif key.keycode == KEY_F2 and _is_enabled:
		_fire_test_magazine()


# Public API

## Projects the weapon's pattern onto a plane `wall_distance` away and returns the
## screen-space-equivalent points, without firing anything.
func compute_pattern(shot_count: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	if weapon == null or weapon.data == null or weapon.data.recoil_pattern == null:
		return result
	var pattern: RecoilPattern = weapon.data.recoil_pattern
	var accumulated := Vector2.ZERO
	for index: int in shot_count:
		accumulated += pattern.get_offset(index)
		result.push_back(Vector2(
			tan(deg_to_rad(accumulated.x)) * wall_distance,
			tan(deg_to_rad(accumulated.y)) * wall_distance))
	return result


func clear() -> void:
	_points.clear()
	_refresh()


# Private

func _bind_weapon() -> void:
	if weapon != null:
		return
	var player := Players.local() as Player
	if player == null:
		# Not an error any more: this runs before the spawner has placed our
		# body, and on a client before it has arrived at all. Retried next call.
		return
	weapon = player.weapon
	aim_node = player.head


func _set_enabled(value: bool) -> void:
	_is_enabled = value
	visible = value
	if value:
		_draw_projected_pattern()
	else:
		clear()


## Draws where the pattern says the rounds will land - the authored intent.
func _draw_projected_pattern() -> void:
	_points.clear()
	if aim_node == null:
		return
	var origin: Vector3 = aim_node.global_position
	var forward: Vector3 = -aim_node.global_transform.basis.z
	var right: Vector3 = aim_node.global_transform.basis.x
	var up: Vector3 = aim_node.global_transform.basis.y
	var magazine: int = weapon.get_magazine_size() if weapon != null else 30
	for point: Vector2 in compute_pattern(magazine):
		_points.push_back(origin + forward * wall_distance + right * point.x + up * point.y)
	_refresh()


## Fires the real weapon a magazine deep and records the actual impact points, so
## authored intent and observed result can be compared side by side.
func _fire_test_magazine() -> void:
	if weapon == null:
		return
	var shots: int = weapon.get_ammo()
	for _i: int in shots:
		weapon.set_trigger(true)
		_record_impact()
		await get_tree().create_timer(1.0 / weapon.get_fire_rate()).timeout
	weapon.set_trigger(false)


func _record_impact() -> void:
	if aim_node == null:
		return
	var origin: Vector3 = aim_node.global_position
	var to: Vector3 = origin - aim_node.global_transform.basis.z * RAY_LENGTH
	var query := PhysicsRayQueryParameters3D.create(origin, to, PhysicsLayers.WORLD)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	_points.push_back(hit["position"])
	_refresh()


func _refresh() -> void:
	if _multimesh == null or _multimesh.multimesh == null:
		return
	var multimesh: MultiMesh = _multimesh.multimesh
	multimesh.instance_count = _points.size()
	for i: int in _points.size():
		multimesh.set_instance_transform(i,
			Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * POINT_SIZE), _points[i]))


func _is_dev_build() -> bool:
	return OS.has_feature("dev") or OS.has_feature("editor")
