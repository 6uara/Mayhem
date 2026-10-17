extends GutTest
## De donde vino cada golpe que recibio el jugador, y el resumen de su muerte.
##
## Es telemetria para el playtest: "murio en la ola 7" no dice si la 7 esta mal
## o si los Rangers de la 6 lo dejaron en un tercio de vida.


func before_each() -> void:
	RunRecord.reset()


func after_each() -> void:
	RunRecord.reset()


func test_a_hit_with_no_attacker_comes_from_the_arena() -> void:
	var health := HealthComponent.new()
	add_child_autofree(health)
	health.apply_damage(10.0)
	assert_eq(health.last_hit_cause, DamageCause.ARENA)


func test_an_explicit_cause_wins_over_the_attacker() -> void:
	var health := HealthComponent.new()
	add_child_autofree(health)
	health.apply_damage(10.0, null, &"bomber")
	assert_eq(health.last_hit_cause, &"bomber")


## A diferencia de `last_attacker`, que es de quien es la muerte, esto describe
## el ultimo golpe: un charco despues de un Ranger dice "arena".
func test_every_hit_overwrites_the_cause() -> void:
	var health := HealthComponent.new()
	add_child_autofree(health)
	health.apply_damage(5.0, null, &"ranger")
	health.apply_damage(5.0)
	assert_eq(health.last_hit_cause, DamageCause.ARENA)


func test_the_player_is_named_as_themselves() -> void:
	var body := Node3D.new()
	body.add_to_group(&"player")
	add_child_autofree(body)
	assert_eq(DamageCause.of(body), DamageCause.SELF)


func test_causes_have_readable_names() -> void:
	assert_eq(DamageCause.label(&"rusher"), "Rusher")
	assert_ne(DamageCause.label(DamageCause.ARENA), "")
	assert_eq(DamageCause.label(&"no_such_thing"), "No Such Thing")


func test_the_run_adds_up_damage_by_cause() -> void:
	EventBus.player_hit.emit(10.0, &"ranger")
	EventBus.player_hit.emit(15.0, &"ranger")
	EventBus.player_hit.emit(5.0, &"bomber")
	assert_eq(float(RunRecord.damage_by_cause[&"ranger"]), 25.0)
	assert_eq(float(RunRecord.damage_by_cause[&"bomber"]), 5.0)


func test_the_last_hit_before_dying_is_the_killer() -> void:
	EventBus.player_hit.emit(60.0, &"ranger")
	EventBus.player_hit.emit(40.0, &"bomber")
	EventBus.player_died.emit()
	var recap: Dictionary = RunRecord.get_death_recap()
	assert_eq(StringName(recap["killed_by"]), &"bomber")
	assert_eq(StringName(recap["top_cause"]), &"ranger")
	assert_almost_eq(float(recap["top_share"]), 0.6, 0.001)


func test_the_end_screen_names_the_killer_and_the_real_problem() -> void:
	var line: String = load("res://scripts/ui/match_overlay.gd").death_recap_line({
		"killed_by": &"bomber", "top_cause": &"ranger", "top_share": 0.62})
	assert_string_contains(line, "Killed by Bomber")
	assert_string_contains(line, "62% of your damage came from Ranger")


func test_no_killer_means_no_recap() -> void:
	assert_eq(load("res://scripts/ui/match_overlay.gd").death_recap_line({}), "")
