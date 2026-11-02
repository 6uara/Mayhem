extends GutTest
## El peso del disparo sin frenar el tiempo: un sacudon leve de camara y un
## oscurecimiento leve de los bordes. Lo que se prueba es que existan, que sean
## leves y que respeten las opciones de accesibilidad.

const SettingsGuard = preload("res://tests/settings_guard.gd")
const PULSE_SCRIPT := preload("res://scripts/ui/shot_pulse_overlay.gd")
const PULSE_SHADER: Shader = preload("res://assets/shaders/shot_pulse.gdshader")

var _guard: SettingsGuard = SettingsGuard.new()
var _recoil: CameraRecoilComponent
var _rig: Node3D


func before_each() -> void:
	_guard.take()
	SettingsManager.set_value("accessibility/screenshake_enabled", true)
	SettingsManager.set_value("accessibility/reduce_flashing", false)
	_rig = Node3D.new()
	add_child_autofree(_rig)
	_recoil = CameraRecoilComponent.new()
	_recoil.camera_rig = _rig
	add_child_autofree(_recoil)


func after_each() -> void:
	_guard.restore()


func _pulse() -> ShotPulseOverlay:
	var overlay: ShotPulseOverlay = PULSE_SCRIPT.new()
	var material := ShaderMaterial.new()
	material.shader = PULSE_SHADER
	overlay.material = material
	add_child_autofree(overlay)
	return overlay


# ----------------------------------------------------------------- el sacudon

func test_a_shot_shakes_the_camera_a_little() -> void:
	_recoil.apply_shot(Vector2(0.0, 1.0), 12.0, 1.0)
	assert_gt(_recoil.get_trauma(), 0.0, "el tiro sacude")
	assert_lte(_recoil.get_trauma() * _recoil.shake_roll_degrees, 0.2,
		"un tiro suelto es una decima de grado, no un temblor")


func test_full_auto_never_shakes_past_its_ceiling() -> void:
	for _i: int in 200:
		_recoil.apply_shot(Vector2(0.0, 1.0), 12.0, 1.6)
	assert_lte(_recoil.get_trauma(), 1.0)
	assert_lte(_recoil.shake_roll_degrees, 1.0, "aun al tope, menos de un grado")


func test_the_shake_settles_on_its_own() -> void:
	_recoil.apply_shot(Vector2(0.0, 1.0), 12.0, 1.0)
	_recoil._process(1.0)
	assert_eq(_recoil.get_trauma(), 0.0)
	assert_almost_eq(_rig.rotation_degrees.z, 0.0, 0.0001, "sin sacudon, sin roll")
	assert_eq(_rig.position, Vector3.ZERO, "y el rig vuelve a su lugar")


func test_screenshake_off_means_no_shake() -> void:
	SettingsManager.set_value("accessibility/screenshake_enabled", false)
	_recoil.apply_shot(Vector2(0.0, 1.0), 12.0, 1.0)
	assert_eq(_recoil.get_trauma(), 0.0)


func test_the_shake_never_moves_the_aim() -> void:
	_recoil.apply_shot(Vector2.ZERO, 12.0, 1.0)
	_recoil._process(0.016)
	assert_eq(_recoil.aim_offset, Vector2.ZERO, "el sacudon es solo del rig")


# ------------------------------------------------------------------- el pulso

func test_a_shot_darkens_the_edges_faintly() -> void:
	var overlay: ShotPulseOverlay = _pulse()
	EventBus.weapon_fired.emit(&"pistol")
	assert_almost_eq(overlay.get_intensity(), Tokens.SHOT_PULSE_ALPHA, 0.001)
	assert_true(overlay.visible)
	assert_lte(Tokens.KILL_PULSE_ALPHA, 0.2, "ni la kill llena la pantalla")


func test_a_kill_pulses_harder_and_a_shot_does_not_cut_it_short() -> void:
	var overlay: ShotPulseOverlay = _pulse()
	EventBus.kill_scored.emit(&"rusher", Vector3.ZERO, false, 10)
	EventBus.weapon_fired.emit(&"pistol")
	assert_almost_eq(overlay.get_intensity(), Tokens.KILL_PULSE_ALPHA, 0.001)


func test_the_pulse_fades_and_hides_itself() -> void:
	var overlay: ShotPulseOverlay = _pulse()
	EventBus.weapon_fired.emit(&"pistol")
	overlay._process(Tokens.SHOT_PULSE_LIFE + 0.01)
	assert_eq(overlay.get_intensity(), 0.0)
	assert_false(overlay.visible, "en reposo no cuesta ni un pixel")


func test_reduce_flashing_turns_the_pulse_off() -> void:
	SettingsManager.set_value("accessibility/reduce_flashing", true)
	var overlay: ShotPulseOverlay = _pulse()
	EventBus.weapon_fired.emit(&"pistol")
	assert_eq(overlay.get_intensity(), 0.0)
