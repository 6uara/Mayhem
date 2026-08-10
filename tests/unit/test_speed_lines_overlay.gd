extends GutTest
## The screen-space speed-line vignette: stays off at walking speed, ramps
## smoothly (not instantly) toward full intensity, and respects its own
## accessibility toggle.

var _overlay: SpeedLinesOverlay
var _original_setting: bool


func before_each() -> void:
	_original_setting = bool(SettingsManager.get_value("accessibility/speed_lines_enabled", true))
	SettingsManager.set_value("accessibility/speed_lines_enabled", true)
	_overlay = add_child_autofree(SpeedLinesOverlay.new())
	_overlay.material = ShaderMaterial.new()
	_overlay.material.shader = load("res://assets/shaders/speed_lines.gdshader")
	_overlay.min_speed = 10.0
	_overlay.max_speed = 20.0
	_overlay.smoothing = 100.0  # fast enough that one tick is enough in tests
	await wait_physics_frames(1)


func after_each() -> void:
	SettingsManager.set_value("accessibility/speed_lines_enabled", _original_setting)


func test_speed_lines_stay_off_at_walking_speed() -> void:
	_overlay.set_speed(6.0)
	await wait_physics_frames(3)
	assert_almost_eq(_overlay._shown_intensity, 0.0, 0.01)


func test_speed_lines_ramp_with_horizontal_speed() -> void:
	_overlay.set_speed(15.0)  # halfway between min and max
	await wait_physics_frames(20)
	assert_almost_eq(_overlay._shown_intensity, 0.5, 0.05)


func test_speed_lines_cap_at_full_intensity_past_max_speed() -> void:
	_overlay.set_speed(999.0)
	await wait_physics_frames(20)
	assert_almost_eq(_overlay._shown_intensity, 1.0, 0.01)


func test_intensity_never_jumps_instantly() -> void:
	_overlay.smoothing = 0.5  # slow, so one frame cannot reach the target
	_overlay.set_speed(999.0)
	await wait_physics_frames(1)
	assert_lt(_overlay._shown_intensity, 1.0,
		"a single frame must not snap straight to full intensity")


func test_turning_speed_lines_off_forces_zero_intensity() -> void:
	SettingsManager.set_value("accessibility/speed_lines_enabled", false)
	_overlay.set_speed(999.0)
	await wait_physics_frames(20)
	assert_almost_eq(_overlay._shown_intensity, 0.0, 0.01)
