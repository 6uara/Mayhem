extends GutTest
## The shader wipe GameManager plays around every scene change.

var _transition: SceneTransition


func before_each() -> void:
	_transition = add_child_autofree(
		load("res://scenes/ui/scene_transition.tscn").instantiate())
	_transition.duration = 0.05
	await wait_physics_frames(1)


func test_starts_hidden() -> void:
	assert_false(_transition.get_node("Rect").visible)


func test_fade_out_covers_the_screen() -> void:
	await _transition.fade_out()
	var rect: ColorRect = _transition.get_node("Rect")
	assert_true(rect.visible)
	var material: ShaderMaterial = rect.material
	assert_almost_eq(float(material.get_shader_parameter(&"t")), 1.0, 0.01)


func test_fade_in_reveals_and_hides_the_rect_again() -> void:
	await _transition.fade_out()
	await _transition.fade_in()
	var rect: ColorRect = _transition.get_node("Rect")
	assert_false(rect.visible, "a fully revealed transition must stop blocking input/clicks")
	var material: ShaderMaterial = rect.material
	assert_almost_eq(float(material.get_shader_parameter(&"t")), 0.0, 0.01)


## safety_timeout is exported specifically so this doesn't have to actually
## wait out the real 3-second default to prove the ceiling works.
func test_a_stalled_fade_is_forced_to_finish_rather_than_hanging_forever() -> void:
	_transition.duration = 999.0
	_transition.safety_timeout = 0.05

	await _transition.fade_out()

	var material: ShaderMaterial = _transition.get_node("Rect").material
	assert_almost_eq(float(material.get_shader_parameter(&"t")), 1.0, 0.01,
		"the ceiling must force the target value even though the tween never finished")
