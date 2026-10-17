extends GutTest
## Los pedidos del publico: "queremos un 360". Un bono de estilo convertido en una
## meta de veinte segundos, que paga en rating, en plata y con un regalo.


func before_each() -> void:
	CrowdRequests.reset()
	CrowdRequests.enabled = false
	BroadcastRating.reset()
	BroadcastRating.tracking = true
	EconomyManager.reset()


func after_each() -> void:
	CrowdRequests.reset()
	CrowdRequests.enabled = false
	BroadcastRating.tracking = false
	BroadcastRating.reset()
	EconomyManager.reset()


func _request(bonus_id: StringName = &"spin", goal: int = 2) -> CrowdRequest:
	var request := CrowdRequest.new()
	request.id = &"test_request"
	request.title = "TEST"
	request.bonus_id = bonus_id
	request.goal = goal
	request.time_limit = 10.0
	request.reward_rating = 20.0
	request.reward_currency = 50
	return request


func _kill(bonuses: Array) -> void:
	EventBus.kill_payout.emit(10, bonuses, 0, Vector3.ZERO)


func test_only_kills_with_the_asked_bonus_count() -> void:
	CrowdRequests.start_request(_request(&"spin", 2))
	_kill([&"headshot"])
	assert_eq(CrowdRequests.progress, 0)
	_kill([&"spin", &"airborne"])
	assert_eq(CrowdRequests.progress, 1)


func test_meeting_a_request_pays_rating_and_money() -> void:
	watch_signals(EventBus)
	CrowdRequests.start_request(_request(&"spin", 2))
	_kill([&"spin"])
	var before: float = BroadcastRating.value
	_kill([&"spin"])
	assert_null(CrowdRequests.active, "cumplido, se cierra")
	assert_signal_emitted_with_parameters(EventBus, "crowd_request_ended",
		[&"test_request", true])
	# La kill misma tambien sube el rating; el pedido suma lo suyo encima.
	assert_gte(BroadcastRating.value, before + 20.0)
	assert_eq(EconomyManager.currency,
		int(round(50 * EconomyManager.config.currency_multiplier)))


func test_running_out_of_time_fails_without_paying() -> void:
	watch_signals(EventBus)
	CrowdRequests.enabled = true
	EventBus.wave_started.emit(3, null)
	CrowdRequests.start_request(_request())
	CrowdRequests._process(11.0)
	assert_null(CrowdRequests.active)
	assert_signal_emitted_with_parameters(EventBus, "crowd_request_ended",
		[&"test_request", false])
	assert_eq(EconomyManager.currency, 0)
	EventBus.wave_completed.emit(3, 10.0, 0.0)


func test_a_request_does_not_outlive_its_wave() -> void:
	CrowdRequests.start_request(_request())
	EventBus.wave_completed.emit(3, 10.0, 0.0)
	assert_null(CrowdRequests.active)


func test_the_crowd_asks_on_its_own_during_a_wave() -> void:
	CrowdRequests.enabled = true
	EventBus.wave_started.emit(3, null)
	CrowdRequests._process(CrowdRequests.pool.first_delay + 0.1)
	assert_not_null(CrowdRequests.active)
	EventBus.wave_completed.emit(3, 10.0, 0.0)


func test_the_first_wave_is_quiet() -> void:
	CrowdRequests.enabled = true
	EventBus.wave_started.emit(0, null)
	CrowdRequests._process(CrowdRequests.pool.first_delay * 4.0)
	assert_null(CrowdRequests.active)
	EventBus.wave_completed.emit(0, 10.0, 0.0)


func test_nothing_is_asked_unless_the_match_turns_it_on() -> void:
	EventBus.wave_started.emit(3, null)
	CrowdRequests._process(CrowdRequests.pool.first_delay * 4.0)
	assert_null(CrowdRequests.active)
	EventBus.wave_completed.emit(3, 10.0, 0.0)


func test_the_same_request_never_comes_twice_in_a_row() -> void:
	var last: StringName = &""
	for _i: int in 30:
		var request: CrowdRequest = CrowdRequests.pick()
		assert_ne(request.id, last)
		last = request.id
		CrowdRequests._last_id = request.id


## Un pedido por un bono que no existe no se puede cumplir nunca.
func test_every_request_asks_for_a_bonus_that_exists() -> void:
	assert_gt(CrowdRequests.pool.requests.size(), 0)
	for request: CrowdRequest in CrowdRequests.pool.requests:
		assert_true(KillBonusTracker.BONUS_LABEL.has(request.bonus_id),
			"%s pide %s" % [request.id, request.bonus_id])
		assert_gt(request.goal, 0, String(request.id))
		assert_gt(request.time_limit, 0.0, String(request.id))
		assert_ne(request.title, "", String(request.id))
		assert_not_null(CrowdRequests.find(request.id))
