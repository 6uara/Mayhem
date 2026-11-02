extends GutTest
## La pantalla de fin desarmada: el grafico de oleadas y el resumen que lee
## RunRecord.


func before_each() -> void:
	RunRecord.reset()


func after_each() -> void:
	RunRecord.reset()


func _wave(index: int, duration: float, damage: float, cleared: bool = true) -> Dictionary:
	return {"wave": index, "duration": duration, "damage": damage, "kills": 5,
		"cleared": cleared}


func test_a_flawless_wave_is_cyan_and_a_costly_one_goes_red() -> void:
	assert_eq(WaveChart.bar_color(0.0), Tokens.PLAYER)
	assert_true(WaveChart.bar_color(WaveChart.DAMAGE_FULL_RED * 2.0).is_equal_approx(Tokens.ENEMY))


func test_the_highlights_name_the_fastest_slowest_and_most_hurt_wave() -> void:
	var waves: Array[Dictionary] = [_wave(0, 20.0, 0.0), _wave(1, 50.0, 10.0),
		_wave(2, 30.0, 40.0)]
	var text: String = WaveChart.highlights(waves)
	assert_string_contains(text, "FASTEST W1")
	assert_string_contains(text, "SLOWEST W2")
	assert_string_contains(text, "MOST HURT W3")


## La oleada de la muerte no es "la mas lenta": no termino.
func test_the_wave_you_died_on_is_not_a_highlight() -> void:
	var waves: Array[Dictionary] = [_wave(0, 20.0, 0.0), _wave(1, 90.0, 80.0, false)]
	assert_false(WaveChart.highlights(waves).contains("W2"))


func test_hovering_a_bar_gives_its_numbers() -> void:
	var chart: WaveChart = add_child_autofree(WaveChart.new())
	chart.size = Vector2(500.0, 150.0)
	chart.set_entries([_wave(0, 20.0, 0.0)] as Array[Dictionary], 10)
	assert_string_contains(chart._get_tooltip(Vector2(5.0, 50.0)), "Wave 1")
	assert_string_contains(chart._get_tooltip(Vector2(495.0, 50.0)), "not reached")


func _show(info: Dictionary) -> RunSummary:
	var summary: RunSummary = add_child_autofree(RunSummary.new())
	summary.show_run(info)
	return summary


func test_beating_the_best_says_so() -> void:
	var summary: RunSummary = _show({"score": 900, "previous_best": 500})
	var badge: Label = summary.find_child("BestBadge", true, false)
	assert_eq(badge.text, "NEW BEST")


func test_falling_short_of_the_best_shows_the_gap() -> void:
	var summary: RunSummary = _show({"score": 400, "previous_best": 500})
	var badge: Label = summary.find_child("BestBadge", true, false)
	assert_string_contains(badge.text, "-100")


func test_a_death_names_the_killer_and_a_win_does_not() -> void:
	RunRecord.killed_by = &"rusher"
	var lost: RunSummary = _show({"victory": false})
	assert_not_null(lost.find_child("KilledBy", true, false))
	var won: RunSummary = _show({"victory": true})
	assert_null(won.find_child("KilledBy", true, false))


func test_the_score_breakdown_has_one_piece_per_source() -> void:
	var summary: RunSummary = _show({"score": 100, "breakdown":
		{"kills": 50, "style": 30, "waves": 20, "bonus": 0}})
	var bar: HBoxContainer = summary.find_child("Breakdown", true, false)
	assert_eq(bar.get_child_count(), 3, "lo que no sumo no ocupa lugar")
