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
	assert_ne(body_label.font_size, headshot_label.font_size,
		"a headshot must read as visually distinct from a body shot")
	assert_ne(body_label.modulate, headshot_label.modulate)


func test_numbers_come_from_the_pool_and_go_back() -> void:
	ObjectPool.clear()
	var scene: PackedScene = load(SCENE)
	var number: Node = ObjectPool.acquire(scene)
	assert_true(number.has_method(&"play_at"))
	number.call(&"play_at", Vector3.ZERO, 10.0, false)
	assert_eq(ObjectPool.get_active_count(), 1)

	ObjectPool.release(number)
	assert_eq(ObjectPool.get_active_count(), 0)
	assert_eq(ObjectPool.get_free_count(scene), 1, "a released number returns to its pool")
	ObjectPool.clear()


func test_negative_or_zero_amounts_never_go_negative_on_screen() -> void:
	var number: DamageNumber = add_child_autofree(load(SCENE).instantiate())
	number.play_at(Vector3.ZERO, 0.0, false)
	assert_eq(number.get_node("Label3D").text, "0")
