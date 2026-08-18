class_name LeggedGait
extends Node
## Walks a legged model by swinging its leg bones, with no animation clips.
##
## The spider bot arrives rigged and empty: nineteen bones and not one keyframe.
## A gait driven from the body's own speed is the cheaper half of the answer and
## the better one for walking specifically - it cannot drift out of sync with the
## movement it is supposed to be showing. An authored walk cycle plays at the
## speed it was authored at, and this enemy's speed is not a constant: rushers
## are fast, a slow field halves them, and a stagger stops them dead. All three
## fall out of this for free, because the cycle *is* the speed.
##
## Authored clips are still the right tool for the poses that are moments rather
## than loops - the attack, the death. This does not stand in their way; it only
## drives the legs, and only while nothing else is.
##
## Legs are found by name: BoneAttachment3D nodes called Leg_<order>_<corner>,
## which is what the model exports. A model that does not follow that convention
## simply gets no gait rather than a broken one.

## Degrees the upper leg swings either side of its rest pose.
@export var swing_degrees: float = 14.0
## How far the knee folds while the leg is in the air.
##
## Rectified rather than a full sine: a knee that bent both ways would push the
## foot through the floor on the half of the cycle it is meant to be standing
## on. Only the swinging half lifts, which is also what stops the walk reading
## as skating - the legs swung without ever leaving the ground.
@export var knee_degrees: float = 18.0
## Steps per metre travelled. Tuned against the rusher's stride: too low and it
## moonwalks, too high and it scurries in place.
@export var steps_per_meter: float = 0.85
## How far the body rides up on each step.
##
## Up rather than down: the rest pose is where the feet touch the floor, so a
## dip would push them through it. Riding up keeps the contact pose as the
## lowest the model ever sits.
@export var bob_height: float = 0.03
## Speed below which the gait settles back to its rest pose.
@export var idle_speed_threshold: float = 0.35
## How fast the legs return to rest when the body stops.
@export var settle_speed: float = 6.0

var _skeleton: Skeleton3D
var _body: Node3D
## Bone index -> the axis, in that bone's own frame, that swings it forward.
var _swing_axis: Dictionary = {}
## Bone index -> its phase offset in the cycle, in radians.
var _phase_offset: Dictionary = {}
## Bone index -> how far that bone swings.
var _amplitude: Dictionary = {}
## Bone index -> whether it is a knee, and so only bends one way.
var _is_knee: Dictionary = {}
var _model: Node3D
var _model_rest_y: float = 0.0
var _phase: float = 0.0
var _weight: float = 0.0


## Returns false when the model has no legs this can drive, so the caller can
## drop the component rather than pay for a per-frame no-op.
func setup(model: Node3D, body: Node3D) -> bool:
	_model = model
	_body = body
	_skeleton = _find_skeleton(model)
	if _skeleton == null or _body == null:
		return false
	_model_rest_y = model.position.y
	_collect_legs(model)
	return not _swing_axis.is_empty()


func _physics_process(delta: float) -> void:
	if _skeleton == null or _body == null:
		return
	var speed: float = Vector2(_body.velocity.x, _body.velocity.z).length() \
		if _body is CharacterBody3D else 0.0

	# The cycle advances with distance covered, not with time. That is what ties
	# a footfall to a metre of ground and keeps the legs from sliding: at half
	# speed the enemy takes the same steps, half as often.
	if speed > idle_speed_threshold:
		_phase += speed * steps_per_meter * TAU * delta
		_weight = minf(_weight + settle_speed * delta, 1.0)
	else:
		_weight = maxf(_weight - settle_speed * delta, 0.0)
	if _weight <= 0.0 and is_zero_approx(_phase):
		return

	for bone: int in _swing_axis:
		var wave: float = sin(_phase + float(_phase_offset[bone]))
		if bool(_is_knee[bone]):
			wave = maxf(wave, 0.0)
		var angle: float = wave * deg_to_rad(float(_amplitude[bone])) * _weight
		var axis: Vector3 = _swing_axis[bone]
		var rest: Transform3D = _skeleton.get_bone_rest(bone)
		_skeleton.set_bone_pose_rotation(bone,
			Quaternion(rest.basis.orthonormalized()) * Quaternion(axis, angle))

	if _model != null:
		# Twice the leg frequency: the body dips once per footfall, and there are
		# two of those per cycle.
		_model.position.y = _model_rest_y + absf(sin(_phase)) * bob_height * _weight


# Private

func _find_skeleton(node: Node) -> Skeleton3D:
	var skeleton := node as Skeleton3D
	if skeleton != null:
		return skeleton
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


## Diagonal pairs move together - front-left with back-right - which is how a
## four-legged walk stays balanced and is what makes it read as a walk rather
## than as a hop.
func _collect_legs(node: Node) -> void:
	for attachment: BoneAttachment3D in _attachments(node):
		var parts: PackedStringArray = attachment.name.split("_")
		if parts.size() < 3 or parts[0] != "Leg":
			continue
		var bone: int = _skeleton.find_bone(attachment.bone_name)
		if bone < 0:
			continue
		var corner: String = parts[2]
		var is_front: bool = corner.begins_with("F")
		var is_left: bool = corner.ends_with("L")
		var offset: float = 0.0 if is_front == is_left else PI
		var is_knee: bool = parts[1] == "01"
		# The knee leads the hip by a quarter cycle: the foot is picked up as the
		# leg starts forward and is back down as it plants.
		_phase_offset[bone] = offset + (PI * 0.5 if is_knee else 0.0)
		_amplitude[bone] = knee_degrees if is_knee else swing_degrees
		_is_knee[bone] = is_knee
		_swing_axis[bone] = _side_axis_in_bone_space(bone)


## The swing has to happen around the model's own left-right axis whichever way
## the bone itself happens to point - the rig has each leg facing its corner, so
## a fixed local axis would swing four legs in four directions.
func _side_axis_in_bone_space(bone: int) -> Vector3:
	var basis: Basis = _skeleton.get_bone_global_rest(bone).basis.orthonormalized()
	return basis.inverse() * Vector3.RIGHT


func _attachments(node: Node) -> Array[BoneAttachment3D]:
	var found: Array[BoneAttachment3D] = []
	var attachment := node as BoneAttachment3D
	if attachment != null:
		found.append(attachment)
	for child: Node in node.get_children():
		found.append_array(_attachments(child))
	return found
