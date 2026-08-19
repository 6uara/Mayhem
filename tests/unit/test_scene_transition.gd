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


## Contra la constante y no contra el numero crudo. Este test decia t == 1.0 y lo
## llamaba "tapa la pantalla" - y con este shader 1.0 es justamente la pantalla
## limpia, asi que pasaba en verde mientras la transicion hacia lo contrario de
## lo que dice su nombre. Un numero no sabe lo que significa.
func test_fade_out_covers_the_screen() -> void:
	await _transition.fade_out()
	var rect: ColorRect = _transition.get_node("Rect")
	assert_true(rect.visible, "tapando, sigue en pantalla")
	var material: ShaderMaterial = rect.material
	assert_almost_eq(float(material.get_shader_parameter(&"t")),
		SceneTransition.COVERED_T, 0.01, "termina tapada")


func test_fade_in_reveals_and_hides_the_rect_again() -> void:
	await _transition.fade_out()
	await _transition.fade_in()
	var rect: ColorRect = _transition.get_node("Rect")
	assert_false(rect.visible, "a fully revealed transition must stop blocking input/clicks")
	var material: ShaderMaterial = rect.material
	assert_almost_eq(float(material.get_shader_parameter(&"t")),
		SceneTransition.CLEAR_T, 0.01, "termina limpia")


## safety_timeout is exported specifically so this doesn't have to actually
## wait out the real 3-second default to prove the ceiling works.
func test_a_stalled_fade_is_forced_to_finish_rather_than_hanging_forever() -> void:
	_transition.duration = 999.0
	_transition.safety_timeout = 0.05

	await _transition.fade_out()

	var material: ShaderMaterial = _transition.get_node("Rect").material
	assert_almost_eq(float(material.get_shader_parameter(&"t")),
		SceneTransition.COVERED_T, 0.01,
		"the ceiling must force the target value even though the tween never finished")


## Los dos extremos tienen que ser distintos y estar en el rango que el shader
## entiende. Si alguien los toca sin mirar el shader, esto lo agarra.
func test_the_two_ends_are_the_shader_range() -> void:
	assert_ne(SceneTransition.COVERED_T, SceneTransition.CLEAR_T,
		"tapada y limpia no pueden ser lo mismo")
	for value: float in [SceneTransition.COVERED_T, SceneTransition.CLEAR_T]:
		assert_between(value, 0.0, 1.0, "el shader espera t entre 0 y 1")


## El rect no puede ser blanco: mientras el shader compila, Godot dibuja el
## ColorRect con su propio color, y un blanco a pantalla completa es un fogonazo.
func test_the_rect_is_not_white_underneath_the_shader() -> void:
	var rect: ColorRect = _transition.get_node("Rect")
	assert_lt(rect.color.r + rect.color.g + rect.color.b, 1.0,
		"debajo del shader el rect tiene que ser oscuro, no blanco")
