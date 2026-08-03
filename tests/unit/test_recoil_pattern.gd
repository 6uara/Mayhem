extends GutTest
## Recoil must be deterministic and learnable - same shot index, same offset, always.


func _make_pattern() -> RecoilPattern:
	var pattern := RecoilPattern.new()
	pattern.points = PackedVector2Array([
		Vector2(0.0, 1.0),
		Vector2(0.0, 1.5),
		Vector2(0.5, 1.2),
		Vector2(-0.6, 1.0),
	])
	return pattern


func test_empty_pattern_returns_zero() -> void:
	var pattern := RecoilPattern.new()
	assert_eq(pattern.get_offset(0), Vector2.ZERO)
	assert_eq(pattern.get_offset(12), Vector2.ZERO)


func test_offsets_follow_the_authored_points() -> void:
	var pattern := _make_pattern()
	assert_eq(pattern.get_offset(0), Vector2(0.0, 1.0))
	assert_eq(pattern.get_offset(2), Vector2(0.5, 1.2))


func test_is_deterministic_across_repeated_calls() -> void:
	var pattern := _make_pattern()
	for index: int in 20:
		assert_eq(pattern.get_offset(index), pattern.get_offset(index),
			"shot %d must be identical every time" % index)


func test_clamps_to_last_point_when_not_looping() -> void:
	var pattern := _make_pattern()
	pattern.loop_after_index = -1
	assert_eq(pattern.get_offset(10), Vector2(-0.6, 1.0))


func test_loops_from_loop_after_index() -> void:
	var pattern := _make_pattern()
	pattern.loop_after_index = 2
	# Points 2..3 repeat: index 4 -> 2, 5 -> 3, 6 -> 2.
	assert_eq(pattern.get_offset(4), Vector2(0.5, 1.2))
	assert_eq(pattern.get_offset(5), Vector2(-0.6, 1.0))
	assert_eq(pattern.get_offset(6), Vector2(0.5, 1.2))


func test_negative_index_is_treated_as_first_shot() -> void:
	var pattern := _make_pattern()
	assert_eq(pattern.get_offset(-3), Vector2(0.0, 1.0))


func test_magnitude_scale_scales_without_randomizing() -> void:
	var pattern := _make_pattern()
	assert_eq(pattern.get_offset(1, 0.5), Vector2(0.0, 0.75))
