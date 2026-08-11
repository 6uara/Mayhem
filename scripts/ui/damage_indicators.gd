class_name DamageIndicators
extends Control
## Directional chevrons at a fixed radius from centre, rotated toward whatever hit
## the player.
##
## This is one of the few things allowed inside the no-UI zone's radius, because it
## is the only way to answer "where is it shooting me from" without making the player
## look away from the crosshair.

const MAX_CHEVRONS: int = 6

@export var chevron_size: Vector2 = Vector2(104, 34)
@export var color: Color = Color("#FF3B54")

## Each entry: { "angle": float, "life": float }
var _hits: Array[Dictionary] = []
var _player: Node3D
var _camera: Camera3D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.player_damaged.connect(_on_player_damaged.unbind(2))


func _process(delta: float) -> void:
	if _hits.is_empty():
		return
	for i: int in range(_hits.size() - 1, -1, -1):
		_hits[i]["life"] = float(_hits[i]["life"]) - delta
		if float(_hits[i]["life"]) <= 0.0:
			_hits.remove_at(i)
	queue_redraw()


func _draw() -> void:
	var centre: Vector2 = size * 0.5
	for i: int in _hits.size():
		var hit: Dictionary = _hits[i]
		var life: float = float(hit["life"])
		var tint: Color = color
		# Newest reads strongest; older hits stay visible but recede.
		tint.a = (0.9 if i == _hits.size() - 1 else 0.45)
		# Fade out over the last 400ms of the chevron's life.
		if life < 0.4:
			tint.a *= life / 0.4

		var angle: float = float(hit["angle"])
		var direction := Vector2(sin(angle), -cos(angle))
		var tip: Vector2 = centre + direction * Tokens.DAMAGE_CHEVRON_RADIUS
		_chevron(tip, angle, tint)


# Public API

## `world_direction` points from the player toward the source of the damage.
func add_hit_from(world_direction: Vector3) -> void:
	if not bool(SettingsManager.get_value("hud/damage_indicators", true)):
		return
	_hits.push_back({
		"angle": _screen_angle(world_direction),
		"life": Tokens.DAMAGE_CHEVRON_LIFE,
	})
	if _hits.size() > MAX_CHEVRONS:
		_hits.pop_front()
	queue_redraw()


func clear() -> void:
	_hits.clear()
	queue_redraw()


# Private

## Angle in screen space, 0 = straight ahead, measured around the camera's yaw so
## the chevron points at the attacker rather than at a world axis.
func _screen_angle(world_direction: Vector3) -> float:
	var camera: Camera3D = _get_camera()
	if camera == null:
		return 0.0
	var local: Vector3 = camera.global_transform.basis.inverse() * world_direction
	return atan2(local.x, -local.z)


func _get_camera() -> Camera3D:
	if _camera != null and is_instance_valid(_camera):
		return _camera
	var player := Players.local() as Player
	if player == null:
		return null
	_player = player
	_camera = player.camera
	return _camera


func _chevron(tip: Vector2, angle: float, tint: Color) -> void:
	var forward := Vector2(sin(angle), -cos(angle))
	var right := Vector2(forward.y, -forward.x)
	var half: float = chevron_size.x * 0.5
	draw_colored_polygon(PackedVector2Array([
		tip,
		tip - forward * chevron_size.y + right * half,
		tip - forward * chevron_size.y - right * half]), tint)


## Without a direction the hit still has to register, so it lands dead ahead.
func _on_player_damaged() -> void:
	if _hits.is_empty() or _hits[-1]["life"] < Tokens.DAMAGE_CHEVRON_LIFE - 0.05:
		add_hit_from(_last_attacker_direction())


func _last_attacker_direction() -> Vector3:
	# Nearest live enemy is the best guess when the damage source is not reported.
	var player: Node3D = _player if _player != null else Players.local()
	if player == null:
		return Vector3.FORWARD
	var closest: Vector3 = Vector3.FORWARD
	var best: float = INF
	for node: Node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := node as Node3D
		if enemy == null:
			continue
		var offset: Vector3 = enemy.global_position - player.global_position
		var distance: float = offset.length_squared()
		if distance < best:
			best = distance
			closest = offset
	return closest
