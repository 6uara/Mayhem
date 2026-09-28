extends GutTest
## Pooled floating damage numbers: text, headshot styling, and pool return.

const SCENE: String = "res://scenes/vfx/damage_number.tscn"


func test_a_hit_shows_its_rounded_amount() -> void:
	var number: DamageNumber = add_child_autofree(load(SCENE).instantiate())
	number.play_at(Vector3.ZERO, 42.6, false)
	assert_eq(number.get_node("Label3D").text, "43")


func test_headshots_read_differently_from_body_shots() -> void:
	var body: DamageNumber = add_child_autofree(load(SCENE).instantiate())
	body.play_at(Vector3.ZERO, 20.0, false)
	var headshot: DamageNumber = add_child_autofree(load(SCENE).instantiate())
	headshot.play_at(Vector3.ZERO, 20.0, true)

	var body_label: Label3D = body.get_node("Label3D")
	var headshot_label: Label3D = headshot.get_node("Label3D")
	# Por escala del nodo y no por font_size: cambiar el tamaño de fuente en
	# runtime obliga a rasterizar la fuente de nuevo, que era la mitad del costo
	# que reporto el playtest. La distincion visual es la misma.
	assert_gt(headshot.scale.x, body.scale.x,
		"a headshot must read as visually distinct from a body shot")
	assert_eq(body_label.font_size, headshot_label.font_size,
		"y con el mismo tamaño de fuente, que es lo que lo hace barato")
	assert_ne(body_label.modulate, headshot_label.modulate)


## El numero no se anima solo: lo avanza el spawner con tick(), y tick() avisa
## cuando termino para que vuelva al anillo.
func test_tick_runs_the_number_out_and_stop_hides_it() -> void:
	var number: DamageNumber = add_child_autofree(load(SCENE).instantiate())
	number.play_at(Vector3.ZERO, 10.0, false)
	assert_true(number.visible)
	assert_true(number.tick(DamageNumber.LIFETIME * 0.5), "a mitad de vida sigue")
	assert_gt(number.global_position.y, 0.0, "y va subiendo")
	assert_false(number.tick(DamageNumber.LIFETIME), "pasada la vida, termino")

	number.stop()
	assert_false(number.visible)
	assert_false(number.is_playing())


func test_each_play_gets_a_new_play_id() -> void:
	var number: DamageNumber = add_child_autofree(load(SCENE).instantiate())
	number.play_at(Vector3.ZERO, 10.0, false)
	var first: int = number.play_id
	number.play_at(Vector3.ZERO, 10.0, false)
	assert_ne(number.play_id, first)


func test_negative_or_zero_amounts_never_go_negative_on_screen() -> void:
	var number: DamageNumber = add_child_autofree(load(SCENE).instantiate())
	number.play_at(Vector3.ZERO, 0.0, false)
	assert_eq(number.get_node("Label3D").text, "0")
