class_name ViewmodelArmIK
extends SkeletonModifier3D
## IK de dos huesos para los brazos del viewmodel, y la muñeca orientada al arma.
##
## Los clips de fp_arms.glb mueven dedos y muñeca, nunca donde esta la mano: las
## cuatro armas tienen la empuñadura y el guardamanos en lugares distintos, y un
## clip autorado para una dejaria la otra mano en el aire. La mano va a donde
## `ViewmodelArms` le diga, y el codo sale de esto.
##
## Escrito a mano y no con TwoBoneIK3D porque ademas de la posicion hay que
## orientar la mano (la palma contra la empuñadura), y eso depende de medir la
## mano en la pose actual - nudillos, indice, meñique -, no de los ejes con que
## llegaron los huesos del glTF. Todo se resuelve por giros relativos a la pose
## que dejo la animacion, asi que no importa como venga orientado cada hueso.

## Una cadena hombro-codo-muñeca y a donde tiene que llegar.
class Arm:
	var upper: int = -1
	var lower: int = -1
	var hand: int = -1
	## Para medir la mano: nudillo del medio (adelante) e indice y meñique (costado).
	var knuckle: int = -1
	var index_knuckle: int = -1
	var pinky_knuckle: int = -1
	var is_right: bool = true
	## Todo en el espacio de `space`.
	var wrist: Vector3 = Vector3.ZERO
	var pole: Vector3 = Vector3.DOWN
	## Hacia donde apuntan los nudillos y hacia donde mira la palma. Cero es "no
	## orientar la mano", y queda la del clip.
	var forward: Vector3 = Vector3.ZERO
	var palm: Vector3 = Vector3.ZERO

	func is_valid() -> bool:
		return upper >= 0 and lower >= 0 and hand >= 0


## El nodo en cuyo espacio estan los objetivos (ViewmodelArms).
var space: Node3D
var right: Arm = Arm.new()
var left: Arm = Arm.new()


## Busca los huesos de un lado por nombre. Devuelve false si al esqueleto le
## falta alguno, y ese brazo queda sin IK en vez de romper.
func bind_arm(arm: Arm, skeleton: Skeleton3D, side: String, is_right: bool) -> bool:
	arm.is_right = is_right
	arm.upper = skeleton.find_bone("upper_arm.%s" % side)
	arm.lower = skeleton.find_bone("forearm.%s" % side)
	arm.hand = skeleton.find_bone("hand.%s" % side)
	arm.knuckle = skeleton.find_bone("f_middle.01.%s" % side)
	arm.index_knuckle = skeleton.find_bone("f_index.01.%s" % side)
	arm.pinky_knuckle = skeleton.find_bone("f_pinky.01.%s" % side)
	return arm.is_valid()


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null or space == null or not space.is_inside_tree():
		return
	var to_skeleton: Transform3D = skeleton.global_transform.affine_inverse() \
		* space.global_transform
	for arm: Arm in [right, left]:
		if arm.is_valid():
			_solve(skeleton, arm, to_skeleton)


# Private

func _solve(skeleton: Skeleton3D, arm: Arm, to_skeleton: Transform3D) -> void:
	var shoulder: Vector3 = skeleton.get_bone_global_pose(arm.upper).origin
	var elbow_now: Vector3 = skeleton.get_bone_global_pose(arm.lower).origin
	var wrist_now: Vector3 = skeleton.get_bone_global_pose(arm.hand).origin
	var upper_length: float = shoulder.distance_to(elbow_now)
	var lower_length: float = elbow_now.distance_to(wrist_now)
	if upper_length < 0.0001 or lower_length < 0.0001:
		return

	var target: Vector3 = to_skeleton * arm.wrist
	var pole: Vector3 = to_skeleton * arm.pole
	var reach: Vector3 = target - shoulder
	if reach.length_squared() < 0.000001:
		return
	var along: Vector3 = reach.normalized()
	# Ni del todo estirado ni plegado sobre si mismo: en los dos extremos el plano
	# del codo deja de estar definido y el brazo salta de un lado al otro.
	var distance: float = clampf(reach.length(), absf(upper_length - lower_length) + 0.001,
		upper_length + lower_length - 0.001)
	var bend: Vector3 = pole - shoulder
	bend -= along * bend.dot(along)
	if bend.length_squared() < 0.000001:
		bend = along.cross(Vector3.RIGHT)
	bend = bend.normalized()
	var cos_shoulder: float = clampf((upper_length * upper_length + distance * distance
		- lower_length * lower_length) / (2.0 * upper_length * distance), -1.0, 1.0)
	var elbow: Vector3 = shoulder + (along * cos_shoulder
		+ bend * sqrt(1.0 - cos_shoulder * cos_shoulder)) * upper_length
	var wrist: Vector3 = shoulder + along * distance

	var upper_pose: Transform3D = skeleton.get_bone_global_pose(arm.upper)
	upper_pose.basis = _arc(elbow_now - shoulder, elbow - shoulder) * upper_pose.basis
	skeleton.set_bone_global_pose(arm.upper, upper_pose)

	var lower_pose: Transform3D = skeleton.get_bone_global_pose(arm.lower)
	var hand_origin: Vector3 = skeleton.get_bone_global_pose(arm.hand).origin
	lower_pose.basis = _arc(hand_origin - lower_pose.origin, wrist - lower_pose.origin) \
		* lower_pose.basis
	skeleton.set_bone_global_pose(arm.lower, lower_pose)

	if arm.forward == Vector3.ZERO or arm.knuckle < 0 or arm.index_knuckle < 0 \
			or arm.pinky_knuckle < 0:
		return
	var hand_pose: Transform3D = skeleton.get_bone_global_pose(arm.hand)
	var current: Basis = _hand_frame(skeleton, arm, hand_pose.origin)
	var wanted: Basis = _frame((to_skeleton.basis * arm.forward).normalized(),
		(to_skeleton.basis * arm.palm).normalized())
	hand_pose.basis = (wanted * current.inverse()) * hand_pose.basis
	skeleton.set_bone_global_pose(arm.hand, hand_pose)


## La mano medida en la pose actual: nudillos adelante, palma segun el lado.
func _hand_frame(skeleton: Skeleton3D, arm: Arm, wrist: Vector3) -> Basis:
	var forward: Vector3 = (skeleton.get_bone_global_pose(arm.knuckle).origin - wrist) \
		.normalized()
	var across: Vector3 = skeleton.get_bone_global_pose(arm.index_knuckle).origin \
		- skeleton.get_bone_global_pose(arm.pinky_knuckle).origin
	# Con la palma abajo y los dedos adelante, el indice de la derecha queda a la
	# izquierda y el de la izquierda a la derecha: el mismo producto da la palma
	# en una mano y el dorso en la otra.
	var palm: Vector3 = across.cross(forward) if arm.is_right else forward.cross(across)
	return _frame(forward, palm.normalized())


## Base ortonormal con X adelante e Y hacia la palma.
func _frame(forward: Vector3, palm: Vector3) -> Basis:
	var y: Vector3 = palm - forward * palm.dot(forward)
	if y.length_squared() < 0.000001:
		y = forward.cross(Vector3.RIGHT)
	y = y.normalized()
	return Basis(forward, y, forward.cross(y))


## El giro mas corto que lleva una direccion a la otra.
func _arc(from: Vector3, to: Vector3) -> Basis:
	if from.length_squared() < 0.000001 or to.length_squared() < 0.000001:
		return Basis.IDENTITY
	var a: Vector3 = from.normalized()
	var b: Vector3 = to.normalized()
	if a.dot(b) > 0.99999:
		return Basis.IDENTITY
	if a.dot(b) < -0.99999:
		var axis: Vector3 = a.cross(Vector3.UP)
		if axis.length_squared() < 0.000001:
			axis = a.cross(Vector3.RIGHT)
		return Basis(axis.normalized(), PI)
	return Basis(Quaternion(a, b))
