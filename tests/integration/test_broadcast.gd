extends GutTest
## El rating de la transmision y las reglas que el Host sortea por oleada.

const RULE_POOL: String = "res://data/broadcast_rules/rule_pool.tres"


func before_each() -> void:
	BroadcastRating.reset()
	BroadcastRating.tracking = true
	BroadcastRules.reset()
	BroadcastRules.enabled = false
	UpgradeManager.reset()


func after_each() -> void:
	BroadcastRating.tracking = false
	BroadcastRating.reset()
	BroadcastRules.reset()
	BroadcastRules.enabled = false
	UpgradeManager.reset()


func _style_kill(bonuses: Array = [&"headshot"]) -> void:
	EventBus.kill_payout.emit(10, bonuses, 10, Vector3.ZERO)


# ------------------------------------------------------------------ rating

func test_style_kills_raise_the_rating() -> void:
	_style_kill()
	assert_gt(BroadcastRating.value, 0.0)
	assert_gt(BroadcastRating.get_multiplier(), 1.0)


## Lo que pidio el diseño: si despues de kills con estilo vienen kills planas, el
## rating baja.
func test_plain_kills_bring_it_down() -> void:
	for i: int in 5:
		_style_kill([&"headshot", &"airborne"])
	var high: float = BroadcastRating.value
	for i: int in 5:
		_style_kill([])
	assert_lt(BroadcastRating.value, high)


func test_it_cools_off_during_a_wave_but_not_in_the_shop() -> void:
	_style_kill([&"headshot", &"airborne", &"spin"])
	EventBus.wave_started.emit(0, null)
	var before: float = BroadcastRating.value
	BroadcastRating._process(1.0)
	assert_lt(BroadcastRating.value, before, "en pelea se enfria")
	EventBus.wave_completed.emit(0, 10.0, 0.0)
	var frozen: float = BroadcastRating.value
	BroadcastRating._process(1.0)
	assert_eq(BroadcastRating.value, frozen, "en la tienda queda quieto")


func test_speed_and_pace_amplify_the_gain() -> void:
	var still: float = BroadcastRating.gain_for(1, 0.0, 0)
	assert_gt(BroadcastRating.gain_for(1, 24.0, 0), still, "rapido sube mas")
	assert_gt(BroadcastRating.gain_for(1, 0.0, 4), still, "en racha sube mas")
	assert_eq(BroadcastRating.gain_for(0, 24.0, 4), 0.0, "sin estilo no sube nada")


func test_it_stays_between_zero_and_a_hundred() -> void:
	for i: int in 200:
		_style_kill([&"headshot", &"airborne", &"spin", &"mayhem"])
	assert_eq(BroadcastRating.value, BroadcastRating.MAX_VALUE)
	assert_almost_eq(BroadcastRating.get_multiplier(), BroadcastRating.config.max_multiplier,
		0.001)
	BroadcastRating.reset()
	_style_kill([])
	assert_eq(BroadcastRating.value, 0.0)


func test_the_rating_multiplies_the_style_money() -> void:
	EconomyManager.reset()
	EventBus.kill_payout.emit(0, [&"headshot"], 100, Vector3.ZERO)
	var flat: int = EconomyManager.currency
	EconomyManager.reset()
	BroadcastRating._set_value(BroadcastRating.MAX_VALUE)
	EventBus.kill_payout.emit(0, [&"headshot"], 100, Vector3.ZERO)
	assert_gt(EconomyManager.currency, flat)
	EconomyManager.reset()


func test_a_high_rating_makes_the_crowd_throw_sooner() -> void:
	var calm: float = BroadcastRating.get_drop_interval_scale()
	BroadcastRating._set_value(BroadcastRating.MAX_VALUE)
	assert_lt(BroadcastRating.get_drop_interval_scale(), calm)


# ------------------------------------------------------------------ reglas

func _wave(elite: bool = false) -> WaveData:
	var wave := WaveData.new()
	wave.is_elite_wave = elite
	return wave


func test_the_first_waves_play_clean() -> void:
	assert_null(BroadcastRules.pick_for(0, _wave()))
	assert_null(BroadcastRules.pick_for(1, _wave()))
	assert_not_null(BroadcastRules.pick_for(2, _wave()))


func test_elite_waves_stay_as_they_are() -> void:
	assert_null(BroadcastRules.pick_for(4, _wave(true)))


func test_rules_do_not_repeat_until_the_pool_runs_out() -> void:
	var pool: BroadcastRulePool = load(RULE_POOL)
	var seen: Array[StringName] = []
	for i: int in pool.rules.size():
		var rule: BroadcastRule = BroadcastRules.pick_for(2, _wave())
		assert_false(seen.has(rule.id), "%s se repitio" % rule.id)
		seen.append(rule.id)
		BroadcastRules.start_rule(rule)
	BroadcastRules.end_rule()


func test_nothing_happens_unless_the_match_turns_rules_on() -> void:
	EventBus.wave_started.emit(5, _wave())
	assert_null(BroadcastRules.active)


func test_a_rule_lasts_one_wave() -> void:
	BroadcastRules.enabled = true
	EventBus.wave_started.emit(5, _wave())
	assert_not_null(BroadcastRules.active)
	EventBus.wave_completed.emit(5, 10.0, 0.0)
	assert_null(BroadcastRules.active)


func test_a_stat_rule_applies_and_is_taken_back() -> void:
	var rule: BroadcastRule = load("res://data/broadcast_rules/moon_boots.tres")
	var base: float = UpgradeManager.get_stat(StatsComponent.JUMP_VELOCITY, 10.0)
	BroadcastRules.start_rule(rule)
	assert_gt(UpgradeManager.get_stat(StatsComponent.JUMP_VELOCITY, 10.0), base)
	BroadcastRules.end_rule()
	assert_eq(UpgradeManager.get_stat(StatsComponent.JUMP_VELOCITY, 10.0), base)


func test_headshot_night_triples_the_headshot_bonus() -> void:
	var rule: BroadcastRule = load("res://data/broadcast_rules/headshot_night.tres")
	BroadcastRules.start_rule(rule)
	assert_eq(BroadcastRules.bonus_multiplier(&"headshot"), 3.0)
	assert_eq(BroadcastRules.bonus_multiplier(&"airborne"), 1.0)
	BroadcastRules.end_rule()
	assert_eq(BroadcastRules.bonus_multiplier(&"headshot"), 1.0)


func test_every_rule_says_what_it_does() -> void:
	var pool: BroadcastRulePool = load(RULE_POOL)
	for rule: BroadcastRule in pool.rules:
		assert_ne(rule.title, "", String(rule.id))
		assert_ne(rule.description, "", String(rule.id))
