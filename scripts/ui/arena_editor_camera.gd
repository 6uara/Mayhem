class_name ArenaEditorCamera
extends Camera3D
## The builder's camera: orbit, pan, zoom around a focus point on the grid.
##
## Deliberately not the FPS camera. Building is a top-down job - you need to see
## where a piece lands relative to everything else - and the one control the
## player already knows for that is the RTS one: drag to orbit, WASD to pan,
## wheel to zoom.

## Metres per second of panning at the closest zoom. Scaled by distance, so the
## camera crosses the grid in about the same time however far out it is.
const PAN_SPEED: float = 12.0
const ORBIT_SPEED: float = 0.006
const ZOOM_STEP: float = 0.12
const MIN_DISTANCE: float = 8.0
const MAX_DISTANCE: float = 140.0
## Straight down is unusable - nothing casts a readable silhouette - and below
## the floor is meaningless.
const MIN_PITCH: float = -1.4
const MAX_PITCH: float = -0.15
const SMOOTHING: float = 12.0

## Point the camera orbits. Moving it is panning.
var focus: Vector3 = Vector3.ZERO
var distance: float = 48.0
var yaw: float = 0.6
var pitch: float = -0.75

var _is_orbiting: bool = false
var _target_focus: Vector3 = Vector3.ZERO
var _target_distance: float = 48.0


func _ready() -> void:
	_target_focus = focus
	_target_distance = distance
	_apply(1.0)


## Frames the whole grid, so a new arena opens with its floor on screen.
func frame_grid(grid_size: Vector3i, cell_size: Vector3) -> void:
	var extent := Vector3(
		float(grid_size.x) * cell_size.x, 0.0, float(grid_size.z) * cell_size.z)
	_target_focus = Vector3(extent.x * 0.5, 0.0, extent.z * 0.5)
	_target_distance = clampf(maxf(extent.x, extent.z) * 1.1, MIN_DISTANCE, MAX_DISTANCE)


## Frames what is actually built rather than the empty grid around it: opening a
## saved arena should show the arena, not the box it was authored in.
func frame_bounds(min_world: Vector3, max_world: Vector3) -> void:
	_target_focus = (min_world + max_world) * 0.5
	var span: Vector3 = max_world - min_world
	_target_distance = clampf(maxf(span.x, span.z) * 1.4 + MIN_DISTANCE,
		MIN_DISTANCE, MAX_DISTANCE)


func look_at_cell(world_position: Vector3) -> void:
	_target_focus = world_position


func handle_input(event: InputEvent) -> bool:
	var button := event as InputEventMouseButton
	if button != null:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_target_distance = clampf(
				_target_distance * (1.0 - ZOOM_STEP), MIN_DISTANCE, MAX_DISTANCE)
			return true
		if button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_target_distance = clampf(
				_target_distance * (1.0 + ZOOM_STEP), MIN_DISTANCE, MAX_DISTANCE)
			return true
		if button.button_index == MOUSE_BUTTON_RIGHT or button.button_index == MOUSE_BUTTON_MIDDLE:
			_is_orbiting = button.pressed
			return true

	var motion := event as InputEventMouseMotion
	if motion != null and _is_orbiting:
		yaw -= motion.relative.x * ORBIT_SPEED
		pitch = clampf(pitch - motion.relative.y * ORBIT_SPEED, MIN_PITCH, MAX_PITCH)
		return true
	return false


func _process(delta: float) -> void:
	_pan(delta)
	_apply(clampf(delta * SMOOTHING, 0.0, 1.0))


# Private

## Panning is relative to where the camera is looking, not to the world axes:
## "forward" has to mean "further from me" whatever the orbit angle is.
func _pan(delta: float) -> void:
	var input := Vector2(
		Input.get_axis(&"move_left", &"move_right"),
		Input.get_axis(&"move_forward", &"move_back"))
	if input == Vector2.ZERO:
		return
	var forward := Vector3(sin(yaw), 0.0, cos(yaw)).normalized()
	var right := Vector3(forward.z, 0.0, -forward.x)
	var speed: float = PAN_SPEED * (_target_distance / MIN_DISTANCE) * delta
	_target_focus += (right * input.x + forward * input.y) * speed


func _apply(weight: float) -> void:
	focus = focus.lerp(_target_focus, weight)
	distance = lerpf(distance, _target_distance, weight)
	var offset := Vector3(
		cos(pitch) * sin(yaw), -sin(pitch), cos(pitch) * cos(yaw)) * distance
	global_position = focus + offset
	look_at(focus, Vector3.UP)
