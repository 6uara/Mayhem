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

## Los charcos pooleados que ya volvieron siguen en el arbol y en el grupo, asi
## que contar el grupo entero no ve un charco reusado del pool.
func _live_hazards() -> int:
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group(&"hazard"):
		if not node.is_in_group(ObjectPool.RELEASED_GROUP):
			count += 1
	return count


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


# ------------------------------------------------------------------ ofertas y contratos

func _pool() -> BroadcastRulePool:
	return BroadcastRules.pool


func test_the_host_offers_two_different_rules_to_pick_from() -> void:
	BroadcastRules.enabled = true
	BroadcastRules.prepare_offer(4, _wave())
	var offered: Array[BroadcastRule] = BroadcastRules.get_offered_rules()
	assert_eq(offered.size(), _pool().offer_size)
	assert_ne(offered[0].id, offered[1].id)
	assert_eq(BroadcastRules.get_chosen_rule(), offered[0], "sin elegir, la primera")


func test_the_picked_rule_is_the_one_that_plays() -> void:
	BroadcastRules.enabled = true
	BroadcastRules.prepare_offer(4, _wave())
	var second: BroadcastRule = BroadcastRules.get_offered_rules()[1]
	BroadcastRules.choose_rule(second)
	EventBus.wave_started.emit(4, _wave())
	assert_eq(BroadcastRules.active, second)


func test_a_rule_the_host_did_not_offer_cannot_be_picked() -> void:
	BroadcastRules.enabled = true
	BroadcastRules.prepare_offer(4, _wave())
	var outsider := BroadcastRule.new()
	BroadcastRules.choose_rule(outsider)
	assert_ne(BroadcastRules.get_chosen_rule(), outsider)


func test_no_offer_unless_the_match_turns_rules_on() -> void:
	BroadcastRules.prepare_offer(4, _wave())
	assert_false(BroadcastRules.has_offer())


func test_a_signed_contract_plays_with_the_wave_and_pays_on_clear() -> void:
	var chance: float = _pool().contract_chance
	_pool().contract_chance = 1.0
	BroadcastRules.enabled = true
	BroadcastRules.prepare_offer(4, _wave())
	_pool().contract_chance = chance
	var contract: BroadcastRule = BroadcastRules.get_offered_contract()
	assert_not_null(contract)
	BroadcastRules.set_contract_signed(true)
	EventBus.wave_started.emit(4, _wave())
	assert_eq(BroadcastRules.contract, contract)

	EconomyManager.reset()
	var wave := WaveData.new()
	wave.par_time = 60.0
	var breakdown: Dictionary = EconomyManager.award_wave_bonuses(wave, 30.0, true)
	var expected: int = int(round(contract.get_contract_payout(4)
		* EconomyManager.config.currency_multiplier))
	assert_eq(int(breakdown["contract_bonus"]), expected)
	watch_signals(EventBus)
	EventBus.wave_completed.emit(4, 30.0, 0.0)
	assert_signal_emitted_with_parameters(EventBus, "broadcast_contract_settled",
		[contract.id, contract.get_contract_payout(4)])
	assert_null(BroadcastRules.contract)
	EconomyManager.reset()


func test_an_unsigned_contract_does_nothing() -> void:
	var chance: float = _pool().contract_chance
	_pool().contract_chance = 1.0
	BroadcastRules.enabled = true
	BroadcastRules.prepare_offer(4, _wave())
	_pool().contract_chance = chance
	EventBus.wave_started.emit(4, _wave())
	assert_null(BroadcastRules.contract)
	assert_eq(BroadcastRules.get_contract_payout(), 0)


func test_dying_under_contract_pays_nothing() -> void:
	BroadcastRules.start_contract(load("res://data/broadcast_rules/contracts/grounded.tres"))
	watch_signals(EventBus)
	EventBus.player_died.emit()
	assert_signal_emitted_with_parameters(EventBus, "broadcast_contract_settled",
		[&"grounded", 0])


func test_grounded_takes_the_dash_away_and_gives_it_back() -> void:
	BroadcastRules.start_contract(load("res://data/broadcast_rules/contracts/grounded.tres"))
	assert_eq(UpgradeManager.get_stat(StatsComponent.DASH_CHARGES, 3.0), 0.0)
	BroadcastRules.end_rule()
	assert_eq(UpgradeManager.get_stat(StatsComponent.DASH_CHARGES, 3.0), 3.0)


func test_every_contract_has_a_price_and_says_what_it_takes() -> void:
	assert_gt(_pool().contracts.size(), 0)
	for contract: BroadcastRule in _pool().contracts:
		assert_true(contract.is_contract(), "%s no paga nada" % contract.id)
		assert_ne(contract.description, "", String(contract.id))
		assert_false(contract.stat_modifiers.is_empty(),
			"%s no restringe nada: es plata gratis" % contract.id)


func test_no_regular_rule_is_secretly_a_contract() -> void:
	for rule: BroadcastRule in _pool().rules:
		assert_false(rule.is_contract(), String(rule.id))


# ------------------------------------------------------------------ enemigos y arena

func test_heavyweights_beefs_up_every_enemy() -> void:
	BroadcastRules.start_rule(load("res://data/broadcast_rules/heavyweights.tres"))
	assert_eq(BroadcastRules.enemy_multipliers(&"rusher").x, 1.5)
	assert_eq(BroadcastRules.enemy_multipliers(&"flyer").x, 1.5)
	BroadcastRules.end_rule()
	assert_eq(BroadcastRules.enemy_multipliers(&"rusher"), Vector3.ONE)


func test_an_enemy_modifier_can_name_one_archetype() -> void:
	var rule := BroadcastRule.new()
	var modifier := EnemyRuleModifier.new()
	modifier.enemy_id = &"ranger"
	modifier.speed_multiplier = 2.0
	var modifiers: Array[EnemyRuleModifier] = [modifier]
	rule.enemy_modifiers = modifiers
	assert_eq(rule.get_enemy_multipliers(&"ranger").y, 2.0)
	assert_eq(rule.get_enemy_multipliers(&"rusher").y, 1.0)


func test_manhunt_marks_one_every_few_spawns_up_to_its_limit() -> void:
	var rule: BroadcastRule = load("res://data/broadcast_rules/manhunt.tres")
	EventBus.wave_started.emit(4, _wave())
	BroadcastRules.start_rule(rule)
	var marked: int = 0
	for _i: int in rule.mark_every * (rule.mark_limit + 3):
		if BroadcastRules.should_mark_spawn():
			marked += 1
	assert_eq(marked, rule.mark_limit)


func test_killing_a_marked_enemy_pays_the_bounty_once() -> void:
	watch_signals(EventBus)
	BroadcastRules.note_marked_kill()
	EventBus.kill_scored.emit(&"rusher", Vector3.ZERO, false, 10)
	var first: Array = get_signal_parameters(EventBus, "kill_payout", 0)
	assert_true((first[1] as Array).has(KillBonusTracker.BONUS_MARKED))
	EventBus.kill_scored.emit(&"rusher", Vector3.ZERO, false, 10)
	var second: Array = get_signal_parameters(EventBus, "kill_payout", 1)
	assert_false((second[1] as Array).has(KillBonusTracker.BONUS_MARKED),
		"la marca es de esa kill, no de la siguiente")


func test_scorched_earth_leaves_a_burning_pool_where_the_enemy_fell() -> void:
	BroadcastRules.start_rule(load("res://data/broadcast_rules/scorched_earth.tres"))
	var before: int = _live_hazards()
	EventBus.enemy_killed.emit(&"rusher", Vector3(3.0, 0.0, 3.0), 10)
	await wait_physics_frames(1)
	assert_gt(_live_hazards(), before)
	BroadcastRules.end_rule()
	ObjectPool.release_all()


# ------------------------------------------------------------------ consecuencias del rating

func test_reaching_the_top_tier_pays_once_per_wave() -> void:
	EconomyManager.reset()
	EventBus.wave_started.emit(0, null)
	watch_signals(EventBus)
	BroadcastRating._set_value(BroadcastRating.MAX_VALUE)
	var paid: int = EconomyManager.currency
	assert_gt(paid, 0, "el patrocinador paga")
	assert_signal_emit_count(EventBus, "rating_peak", 1)
	BroadcastRating._set_value(0.0)
	BroadcastRating._set_value(BroadcastRating.MAX_VALUE)
	assert_eq(EconomyManager.currency, paid, "subir y bajar no es una canilla")
	assert_signal_emit_count(EventBus, "rating_peak", 1)
	EventBus.wave_completed.emit(0, 10.0, 0.0)
	EconomyManager.reset()


func test_too_long_off_air_and_the_sponsor_walks_out() -> void:
	WaveManager.current_index = 5
	EventBus.wave_started.emit(5, null)
	BroadcastRating._process(BroadcastRating.config.walkout_after + 0.5)
	assert_true(BroadcastRating.is_walked_out())
	BroadcastRating._set_value(BroadcastRating.config.tier_thresholds[1] + 5.0)
	BroadcastRating._process(0.1)
	assert_false(BroadcastRating.is_walked_out(), "en cuanto sale del piso, vuelve")
	EventBus.wave_completed.emit(5, 10.0, 0.0)
	WaveManager.reset()


func test_the_first_waves_never_lose_the_sponsor() -> void:
	WaveManager.current_index = 0
	EventBus.wave_started.emit(0, null)
	BroadcastRating._process(BroadcastRating.config.walkout_after * 3.0)
	assert_false(BroadcastRating.is_walked_out())
	EventBus.wave_completed.emit(0, 10.0, 0.0)
	WaveManager.reset()


func test_without_the_sponsor_the_crowd_holds_its_gifts() -> void:
	var director := CrowdDropDirector.new()
	director.table = load("res://data/crowd_drop_table.tres")
	add_child_autofree(director)
	WaveManager.current_index = 5
	EventBus.wave_started.emit(5, null)
	director._seconds_left = 5.0
	BroadcastRating._process(BroadcastRating.config.walkout_after + 0.5)
	director._process(1.0)
	assert_eq(director.get_seconds_left(), 0.0,
		"el reloj queda en cero: el primer regalo sale apenas vuelva")
	EventBus.wave_completed.emit(5, 10.0, 0.0)
	WaveManager.reset()
