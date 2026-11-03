extends GutTest
## Los mejores momentos de la run: lo que va arriba de la pantalla de fin y en la
## tarjeta para compartir.


func before_each() -> void:
	RunRecord.reset()


func after_each() -> void:
	RunRecord.reset()


func _ids(highlights: Array[Dictionary]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for highlight: Dictionary in highlights:
		ids.append(StringName(highlight["id"]))
	return ids


func test_an_empty_run_has_no_highlights() -> void:
	assert_true(RunHighlights.pick({}).is_empty(), "nada que contar no inventa un momento")


func test_the_most_notable_moment_comes_first_not_the_biggest_number() -> void:
	# 40 m de tiro es un numero mas grande que 5 kills, pero 5 kills en un segundo
	# y medio pesan mas contra su referencia.
	var picked: Array[Dictionary] = RunHighlights.pick({
		"best_burst": 6, "longest_kill": 40.0})
	assert_eq(StringName(picked[0]["id"]), &"burst")
	assert_eq(StringName(picked[1]["id"]), &"longest_kill")


func test_at_most_three_by_default() -> void:
	var picked: Array[Dictionary] = RunHighlights.pick({
		"best_burst": 5, "best_streak": 30, "top_speed": 25.0, "best_style_bonuses": 4,
		"longest_kill": 35.0, "flawless_waves": 4})
	assert_eq(picked.size(), RunHighlights.DEFAULT_COUNT)


func test_a_trickle_is_not_a_moment() -> void:
	var picked: Array[Dictionary] = RunHighlights.pick({"best_streak": 3, "top_speed": 4.0})
	assert_true(picked.is_empty())


func test_the_headshot_share_needs_enough_kills_to_mean_something() -> void:
	assert_false(_ids(RunHighlights.pick({"kills": 5, "headshots": 5})).has(&"headshots"))
	assert_true(_ids(RunHighlights.pick({"kills": 40, "headshots": 20})).has(&"headshots"))


func test_the_fastest_wave_is_measured_against_its_par() -> void:
	var wave_log: Array = [
		{"wave": 0, "duration": 30.0, "par": 40.0, "cleared": true},
		{"wave": 3, "duration": 50.0, "par": 100.0, "cleared": true},
		{"wave": 4, "duration": 10.0, "par": 100.0, "cleared": false},
	]
	var fastest: Dictionary = RunHighlights.fastest_wave(wave_log)
	assert_eq(int(fastest["wave"]), 3, "la que murio no cuenta; la 4 fue la de mejor relacion")
	var picked: Array[Dictionary] = RunHighlights.pick({"wave_log": wave_log})
	assert_eq(String(picked[0]["value"]), "Wave 4")
	assert_eq(String(picked[0]["detail"]), "50% under par")


func test_run_record_counts_a_burst_inside_the_window() -> void:
	for i: int in 3:
		EventBus.kill_scored.emit(&"rusher", Vector3.ZERO, false, 10)
	assert_eq(RunRecord.best_burst, 3)
	RunRecord._run_clock += RunRecord.BURST_WINDOW + 0.1
	EventBus.kill_scored.emit(&"rusher", Vector3.ZERO, false, 10)
	assert_eq(RunRecord.best_burst, 3, "la que llega tarde arranca otra rafaga")


func test_run_record_counts_the_streak_until_a_hit() -> void:
	for i: int in 4:
		EventBus.kill_scored.emit(&"rusher", Vector3.ZERO, false, 10)
	EventBus.player_damaged.emit(5.0, 95.0)
	EventBus.kill_scored.emit(&"rusher", Vector3.ZERO, false, 10)
	assert_eq(RunRecord.best_streak, 4)


func test_run_record_keeps_the_best_style_kill() -> void:
	EventBus.kill_payout.emit(10, [&"headshot"], 15, Vector3.ZERO)
	EventBus.kill_payout.emit(10, [&"headshot", &"airborne", &"spin"], 60, Vector3.ZERO)
	EventBus.kill_payout.emit(10, [&"airborne"], 20, Vector3.ZERO)
	assert_eq(RunRecord.best_style_bonuses, 3)
	assert_eq(RunRecord.best_style_total, 60)


func test_the_wave_log_carries_the_par_time() -> void:
	var wave := WaveData.new()
	wave.par_time = 75.0
	EventBus.wave_started.emit(2, wave)
	EventBus.wave_completed.emit(2, 60.0, 0.0)
	assert_eq(float(RunRecord.wave_log[-1]["par"]), 75.0)


func test_the_share_card_shows_result_score_moments_and_code() -> void:
	var card := ShareCard.new()
	add_child_autofree(card)
	card.build({
		"victory": false, "score": 4200, "reached": "Died on wave 7",
		"context": "The Pit - Arsenal - 9:12", "code": "ABCD-EFGH",
		"highlights": RunHighlights.pick({"best_burst": 5, "longest_kill": 35.0}),
		"trophies": ["ACROBATA"],
	})
	assert_eq((card.find_child("Result", true, false) as Label).text, "DIED ON WAVE 7")
	assert_eq((card.find_child("Score", true, false) as Label).text, "4200 PTS")
	assert_eq(card.find_child("Moments", true, false).get_child_count(), 2)
	assert_string_contains((card.find_child("Code", true, false) as Label).text, "ABCD-EFGH")
	assert_eq(card.custom_minimum_size, Vector2(ShareCard.CARD_SIZE))
