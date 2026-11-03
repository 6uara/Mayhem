extends GutTest
## Las capas del show que el playtest puede apagar: rating, reglas, contratos y
## pedidos del publico. Ver docs/PLAYTEST.md.


func before_each() -> void:
	PlaytestLayers.clear_overrides()
	BroadcastRules.reset()
	BroadcastRules.enabled = false
	BroadcastRating.reset()
	CrowdRequests.reset()
	CrowdRequests.enabled = false


func after_each() -> void:
	PlaytestLayers.clear_overrides()
	BroadcastRules.reset()
	BroadcastRules.enabled = false
	BroadcastRating.tracking = false
	BroadcastRating.reset()
	CrowdRequests.reset()
	CrowdRequests.enabled = false


func _wave() -> WaveData:
	return WaveData.new()


func _always_contract(action: Callable) -> void:
	var pool: BroadcastRulePool = BroadcastRules.pool
	var chance: float = pool.contract_chance
	pool.contract_chance = 1.0
	action.call()
	pool.contract_chance = chance


# ------------------------------------------------------------------ lectura

func test_the_shipped_config_has_every_layer_on() -> void:
	var config := load(PlaytestLayers.CONFIG_PATH) as PlaytestLayersConfig
	assert_not_null(config)
	assert_true(config.rating and config.rules and config.contracts and config.crowd_requests,
		"el juego sale con todo encendido; apagar es cosa de la tanda de prueba")


func test_a_minus_turns_a_layer_off_and_a_plus_turns_it_on() -> void:
	var parsed: Dictionary = PlaytestLayers.parse("-rating,+rules,contracts")
	assert_eq(parsed[PlaytestLayers.RATING], false)
	assert_eq(parsed[PlaytestLayers.RULES], true)
	assert_eq(parsed[PlaytestLayers.CONTRACTS], true)
	assert_false(parsed.has(PlaytestLayers.CROWD_REQUESTS), "lo que no se nombra no se toca")


func test_none_turns_off_all_four() -> void:
	var parsed: Dictionary = PlaytestLayers.parse("none")
	for layer: StringName in PlaytestLayers.ALL:
		assert_eq(parsed[layer], false)


func test_an_unknown_layer_is_ignored() -> void:
	var parsed: Dictionary = PlaytestLayers.parse("-ratting")
	assert_true(parsed.is_empty())


func test_the_disabled_list_names_what_is_off() -> void:
	PlaytestLayers.set_override(PlaytestLayers.CONTRACTS, false)
	assert_eq(PlaytestLayers.get_disabled(), ["contracts"] as Array[String])


# ------------------------------------------------------------------ efecto

func test_without_rules_the_host_offers_only_the_contract() -> void:
	PlaytestLayers.set_override(PlaytestLayers.RULES, false)
	BroadcastRules.enabled = true
	_always_contract(func() -> void: BroadcastRules.prepare_offer(4, _wave()))
	assert_true(BroadcastRules.get_offered_rules().is_empty())
	assert_not_null(BroadcastRules.get_offered_contract())


func test_without_contracts_the_host_offers_only_rules() -> void:
	PlaytestLayers.set_override(PlaytestLayers.CONTRACTS, false)
	BroadcastRules.enabled = true
	_always_contract(func() -> void: BroadcastRules.prepare_offer(4, _wave()))
	assert_false(BroadcastRules.get_offered_rules().is_empty())
	assert_null(BroadcastRules.get_offered_contract())


func test_without_rules_a_wave_with_no_offer_plays_clean() -> void:
	PlaytestLayers.set_override(PlaytestLayers.RULES, false)
	BroadcastRules.enabled = true
	EventBus.wave_started.emit(5, _wave())
	assert_null(BroadcastRules.active, "sin oferta, el sorteo de respaldo tambien respeta la capa")


func test_the_match_leaves_the_rating_off_when_its_layer_is_off() -> void:
	PlaytestLayers.set_override(PlaytestLayers.RATING, false)
	MatchDirector.apply_layers(true)
	assert_false(BroadcastRating.tracking)
	EventBus.kill_payout.emit(10, [&"headshot", &"airborne"], 10, Vector3.ZERO)
	assert_eq(BroadcastRating.value, 0.0)
	assert_eq(BroadcastRating.get_multiplier(), 1.0, "el estilo paga sin multiplicar")


func test_the_match_leaves_crowd_requests_off_when_their_layer_is_off() -> void:
	PlaytestLayers.set_override(PlaytestLayers.CROWD_REQUESTS, false)
	MatchDirector.apply_layers(true)
	assert_false(CrowdRequests.enabled)
	assert_true(BroadcastRules.enabled, "las reglas siguen")


func test_with_every_layer_on_the_match_turns_everything_on() -> void:
	MatchDirector.apply_layers(true)
	assert_true(BroadcastRating.tracking)
	assert_true(BroadcastRules.enabled)
	assert_true(CrowdRequests.enabled)


func test_a_scene_without_broadcast_rules_keeps_them_off_whatever_the_layers() -> void:
	MatchDirector.apply_layers(false)
	assert_false(BroadcastRules.enabled)
	assert_false(CrowdRequests.enabled)
	assert_true(BroadcastRating.tracking, "el rating no depende de las reglas")


func test_the_rating_meter_hides_when_the_rating_is_off() -> void:
	PlaytestLayers.set_override(PlaytestLayers.RATING, false)
	var meter := RatingMeter.new()
	add_child_autofree(meter)
	assert_false(meter.visible)


func test_a_feedback_report_says_which_layers_were_off() -> void:
	PlaytestLayers.set_override(PlaytestLayers.RULES, false)
	var report: Dictionary = FeedbackManager.build_report("probando", "Other")
	assert_eq(String(report["layers_off"]), "rules")
	assert_string_contains(FeedbackManager.format_report(report), "layers_off: rules")


func test_the_latest_run_log_is_the_newest_file() -> void:
	var dir: String = "user://test_feedback_runs"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for stamp: String in ["2026-11-01_10-00-00", "2026-11-03_09-00-00", "2026-11-02_23-59-59"]:
		var file: FileAccess = FileAccess.open("%s/run_%s.json" % [dir, stamp], FileAccess.WRITE)
		file.store_string("{}")
		file.close()
	assert_eq(FeedbackManager.latest_run_log(dir).get_file(), "run_2026-11-03_09-00-00.json")
	for file_name: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir).path_join(file_name))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
