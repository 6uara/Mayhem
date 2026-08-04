class_name CameraFeelComponent
extends Node
## Everything the camera does *because the character is moving*: step bob, strafe
## lean, and the punch of a landing.
##
## The movement maths were never the reason the player felt robotic - the camera was.
## A rigid tripod on a moving body reads as a floating sensor, not a person: there is
## no evidence of weight transferring foot to foot, no lean into a turn, and no cost
## to hitting the ground. This component supplies that evidence, and nothing else.
##
## It owns `view_node` outright. That node sits below the aim pivot and above the
## camera, so every offset here is cosmetic by construction:
##
##   HeadPivot   pitch, and where bullets come from   (Player)
##   ViewBob     this component                       (CameraFeelComponent)
##   CameraRig   weapon recoil kick                   (CameraRecoilComponent)
##   Camera3D    field of view                        (Player)
##
## Roll is safe to apply here for a reason worth stating: rotating about the view
## axis leaves the view axis itself unchanged, so a lean can never move a shot.

## Emitted on each footfall, at the bottom of a stride. Audio hangs off this so the
## sound of walking is locked to the sight of it.
signal stepped()

@export var body: CharacterBody3D
@export var movement: MovementComponent
## The cosmetic node between the aim pivot and the camera. Owned entirely by this
## component - nothing else may write its transform.
@export var view_node: Node3D

@export_group("Step bob")
## Metres of travel per full two-step cycle. Phase advances with distance rather
## than time, so the bob is always in step with the ground actually covered -
## it slows as the player slows and stops dead when they do.
@export var stride_length: float = 2.4
@export var bob_vertical: float = 0.05
@export var bob_horizontal: float = 0.035
## Bob fades rather than snaps when leaving or meeting the floor.
@export var bob_blend_speed: float = 7.0
## Aiming steadies the view; a bobbing sight picture is unusable.
@export var bob_ads_scale: float = 0.25

@export_group("Lean")
## Degrees of roll at full sideways input. Small on purpose: this is the difference
## between leaning into a strafe and driving a boat.
@export var strafe_tilt_degrees: float = 1.8
## Extra roll while sliding, where the whole body is committed to the direction.
@export var slide_tilt_degrees: float = 3.2
@export var tilt_speed: float = 7.0

@export_group("Landing")
## Metres of dip per m/s of impact speed.
@export var land_punch_scale: float = 0.011
@export var land_punch_max: float = 0.16
## Spring constants for the recovery. Stiff and lightly damped, so a landing reads
## as a thud that settles rather than a slow sink.
@export var land_stiffness: float = 150.0
@export var land_damping: float = 15.0

@export_group("Audio")
@export var step_sounds: Array[AudioStream] = []
## Below this speed the player is not really walking, so no step fires.
@export var step_min_speed: float = 1.5

var _bob_phase: float = 0.0
var _ground_blend: float = 1.0
var _tilt_degrees: float = 0.0
var _land_offset: float = 0.0
var _land_velocity: float = 0.0
var _rest_position: Vector3 = Vector3.ZERO
var _step_rng := RandomNumberGenerator.new()
var _last_step_sound: int = -1


func _ready() -> void:
	_step_rng.randomize()
	if view_node != null:
		_rest_position = view_node.position
	if movement != null:
		movement.landed.connect(_on_landed)


func _physics_process(delta: float) -> void:
	if view_node == null or body == null:
		return

	var horizontal: Vector3 = Vector3(body.velocity.x, 0.0, body.velocity.z)
	var speed: float = horizontal.length()
	var grounded: bool = body.is_on_floor()

	_tick_bob(speed, grounded, delta)
	_tick_tilt(delta)
	_tick_landing(delta)
	_apply()


# Private

func _tick_bob(speed: float, grounded: bool, delta: float) -> void:
	var target_blend: float = 1.0 if grounded and speed > step_min_speed else 0.0
	_ground_blend = move_toward(_ground_blend, target_blend, bob_blend_speed * delta)

	if not grounded or speed <= step_min_speed:
		return
	# Sliding is one continuous contact, not a sequence of footfalls.
	if movement != null and movement.is_sliding():
		return

	var previous: float = _bob_phase
	_bob_phase += TAU * (speed * delta) / maxf(stride_length, 0.01)

	# A footfall is a half cycle: one per foot. Comparing floor(phase / PI) catches
	# the crossing regardless of how many cycles a long frame covered.
	if int(floor(_bob_phase / PI)) != int(floor(previous / PI)):
		_play_step()
		stepped.emit()


func _tick_tilt(delta: float) -> void:
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var amount: float = slide_tilt_degrees if movement != null and movement.is_sliding() \
		else strafe_tilt_degrees
	_tilt_degrees = move_toward(_tilt_degrees, -input.x * amount, amount * tilt_speed * delta)


## Damped spring rather than a linear return: the overshoot is what makes an impact
## read as the body absorbing it instead of the camera being dragged back.
func _tick_landing(delta: float) -> void:
	if is_zero_approx(_land_offset) and is_zero_approx(_land_velocity):
		return
	var accel: float = -_land_offset * land_stiffness - _land_velocity * land_damping
	_land_velocity += accel * delta
	_land_offset += _land_velocity * delta
	if absf(_land_offset) < 0.0005 and absf(_land_velocity) < 0.005:
		_land_offset = 0.0
		_land_velocity = 0.0


func _apply() -> void:
	var offset := Vector3.ZERO
	if _bob_enabled():
		var scale: float = _ground_blend * _ads_scale()
		# The vertical term is negative-only so the head dips onto each step and never
		# rises above rest: weight going down through a leg, not a bouncing ball.
		offset.y = -absf(sin(_bob_phase)) * bob_vertical * scale
		offset.x = cos(_bob_phase) * bob_horizontal * scale
	offset.y += _land_offset
	view_node.position = _rest_position + offset
	view_node.rotation_degrees.z = _tilt_degrees


func _bob_enabled() -> bool:
	return bool(SettingsManager.get_value("accessibility/view_bob_enabled"))


func _ads_scale() -> float:
	var player := body as Player
	if player == null or player.weapon == null:
		return 1.0
	return lerpf(1.0, bob_ads_scale, player.weapon.ads_progress)


func _on_landed(fall_speed: float) -> void:
	if fall_speed <= 0.0:
		return
	# The punch is a camera shake, so it answers to the same switch shake does.
	if not bool(SettingsManager.get_value("accessibility/screenshake_enabled")):
		return
	var punch: float = minf(fall_speed * land_punch_scale, land_punch_max)
	_land_offset = -punch
	_land_velocity = 0.0


## Never the same sample twice in a row - an identical step repeating on a fixed
## interval is the loudest robotic tell in the whole locomotion loop.
func _play_step() -> void:
	if step_sounds.is_empty() or body == null:
		return
	var index: int = _step_rng.randi_range(0, step_sounds.size() - 1)
	if step_sounds.size() > 1 and index == _last_step_sound:
		index = (index + 1) % step_sounds.size()
	_last_step_sound = index
	AudioPool.play_3d(step_sounds[index], body.global_position, AudioPool.BUS_WORLD)
