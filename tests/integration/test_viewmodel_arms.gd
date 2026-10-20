extends GutTest
## Los brazos del viewmodel: el rig de fp_arms.glb con IK hacia el arma. Nada aca
## puede ver si se ven bien (eso es tools/preview_viewmodel.gd); lo que se fija es
## que las manos vayan a donde esta el arma y que la recarga las suelte y vuelvan.

const ARMS_SCRIPT := preload("res://scripts/components/viewmodel_arms.gd")
## Una caja con forma de rifle, en el espacio del pivot: medio metro de largo.
const RIFLE_BOUNDS := AABB(Vector3(-0.02, -0.15, -0.45), Vector3(0.04, 0.2, 0.7))
const PIVOT := Vector3(0.15, -0.12, -0.36)


func _build() -> ARMS_SCRIPT:
	var arms: ARMS_SCRIPT = ARMS_SCRIPT.new()
	add_child_autofree(arms)
	arms.position = PIVOT
	arms.build(RIFLE_BOUNDS, PIVOT)
	return arms


func _find(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child: Node in node.get_children():
		var found: Node = _find(child, type_name)
		if found != null:
			return found
	return null


func test_the_arms_are_the_rigged_model_with_its_clips() -> void:
	var arms: ARMS_SCRIPT = _build()
	assert_not_null(_find(arms, "Skeleton3D"), "llega el esqueleto")
	var player: AnimationPlayer = _find(arms, "AnimationPlayer")
	assert_not_null(player, "y sus clips")
	for clip: String in ["grip_idle", "fire", "reload", "equip"]:
		assert_true(player.has_animation(clip), "trae %s" % clip)
	assert_not_null(_find(arms, "SkeletonModifier3D"), "y la IK que los lleva al arma")


## La palma va a la empuñadura y al guardamanos; la muñeca queda a un palmo.
func test_the_hands_go_to_the_grip_and_the_handguard() -> void:
	var arms: ARMS_SCRIPT = _build()
	await wait_seconds(ARMS_SCRIPT.EQUIP_TIME + 0.1)
	var wrists: Array[Vector3] = arms.get_wrist_targets()
	assert_eq(wrists.size(), 2)
	var grip: Vector3 = ARMS_SCRIPT.grip_point(RIFLE_BOUNDS)
	var support: Vector3 = ARMS_SCRIPT.support_point(RIFLE_BOUNDS)
	assert_lt(wrists[0].distance_to(grip), 0.15, "la derecha en la empuñadura")
	assert_lt(wrists[1].distance_to(support), 0.15, "la izquierda en el guardamanos")
	assert_lt(support.z, grip.z, "y el guardamanos esta adelante")


## A mitad de recarga la izquierda fue a buscar el cargador, y al terminar vuelve
## exacto al guardamanos: sin estado guardado, por progreso.
func test_reloading_takes_the_left_hand_away_and_back() -> void:
	var arms: ARMS_SCRIPT = _build()
	await wait_seconds(ARMS_SCRIPT.EQUIP_TIME + 0.1)
	var resting: Vector3 = arms.get_wrist_targets()[1]
	arms.set_reload_progress(0.37)
	await wait_process_frames(2)
	assert_gt(arms.get_wrist_targets()[1].distance_to(resting), 0.15,
		"la mano se fue a buscar el cargador")
	arms.set_reload_progress(0.0)
	await wait_process_frames(2)
	assert_almost_eq(arms.get_wrist_targets()[1], resting, Vector3.ONE * 0.001,
		"y volvio al guardamanos")


## Sacar el arma: las manos arrancan abajo y suben.
func test_equipping_brings_the_hands_up_from_below() -> void:
	var arms: ARMS_SCRIPT = _build()
	await wait_process_frames(1)
	var start: float = arms.get_wrist_targets()[0].y
	await wait_seconds(ARMS_SCRIPT.EQUIP_TIME + 0.1)
	assert_gt(arms.get_wrist_targets()[0].y, start + 0.1, "suben hasta el agarre")


func _launcher(arms: ARMS_SCRIPT) -> Node3D:
	return arms.find_child("GrappleLauncher", true, false) as Node3D


## El gancho sale de la muñeca izquierda: el lanzador va colgado del antebrazo
## izquierdo y lo sigue a donde lo lleve la IK.
func test_the_grapple_launcher_rides_the_left_forearm() -> void:
	var arms: ARMS_SCRIPT = _build()
	var launcher: Node3D = _launcher(arms)
	assert_not_null(launcher, "hay lanzador")
	var mount := launcher.get_parent() as BoneAttachment3D
	assert_not_null(mount, "colgado de un hueso")
	assert_eq(mount.bone_name, "forearm.L", "el antebrazo izquierdo")


## Hay un juego de brazos por arma y todos escuchan el EventBus: solo el que se
## ve dispara el gancho.
func test_only_the_visible_arms_fire_the_grapple() -> void:
	var shown: ARMS_SCRIPT = _build()
	var hidden: ARMS_SCRIPT = _build()
	hidden.visible = false
	await wait_process_frames(1)
	EventBus.grapple_started.emit(Vector3(0.0, 8.0, -20.0))
	assert_true(_launcher(shown).call(&"is_grappling"), "el visible engancha")
	assert_false(_launcher(hidden).call(&"is_grappling"), "el guardado no")
	EventBus.grapple_ended.emit()
	assert_false(_launcher(shown).call(&"is_grappling"), "y suelta al terminar")


## Con la pistola las dos manos van juntas y el antebrazo izquierdo queda fuera
## de cuadro: al tirar el gancho la izquierda suelta el arma y se adelanta, que es
## lo que pone el lanzador en pantalla. Al soltar, vuelve.
func test_grappling_brings_the_left_arm_forward() -> void:
	var arms: ARMS_SCRIPT = _build()
	await wait_seconds(ARMS_SCRIPT.EQUIP_TIME + 0.1)
	var holding: Vector3 = arms.get_wrist_targets()[1]
	EventBus.grapple_started.emit(Vector3(0.0, 8.0, -20.0))
	await wait_seconds(ARMS_SCRIPT.GRAPPLE_RAISE_TIME + 0.1)
	assert_gt(arms.get_wrist_targets()[1].distance_to(holding), 0.05, "la mano se fue del arma")
	EventBus.grapple_ended.emit()
	await wait_seconds(ARMS_SCRIPT.GRAPPLE_RAISE_TIME + 0.1)
	assert_almost_eq(arms.get_wrist_targets()[1], holding, Vector3.ONE * 0.001, "y volvio")
