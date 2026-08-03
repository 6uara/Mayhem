extends GutTest
## Deadlock-model dash charges: each spent charge regenerates on its own timer.


func _make(max_charges: int = 2, cooldown: float = 5.0) -> DashCharges:
	var charges := DashCharges.new()
	charges.setup(max_charges, cooldown)
	return charges


func test_starts_full() -> void:
	var charges := _make()
	assert_eq(charges.get_available(), 2)


func test_consume_spends_one_charge_at_a_time() -> void:
	var charges := _make()
	assert_true(charges.try_consume())
	assert_eq(charges.get_available(), 1)
	assert_true(charges.try_consume())
	assert_eq(charges.get_available(), 0)
	assert_false(charges.try_consume(), "no third dash on two charges")


func test_charges_regenerate_independently() -> void:
	var charges := _make(2, 5.0)
	charges.try_consume()
	charges.tick(3.0)          # first charge is 3s into its 5s cooldown
	charges.try_consume()      # second spent now
	charges.tick(2.5)          # first returns (5.5s elapsed), second at 2.5/5
	assert_eq(charges.get_available(), 1,
		"the first charge must come back on its own timer, not wait for the second")
	charges.tick(2.5)
	assert_eq(charges.get_available(), 2)


func test_no_free_charge_from_partial_ticks() -> void:
	var charges := _make(2, 5.0)
	charges.try_consume()
	charges.tick(4.99)
	assert_eq(charges.get_available(), 1)


func test_max_increase_from_upgrade_takes_effect() -> void:
	var charges := _make(2, 5.0)
	charges.set_max_charges(3)
	assert_eq(charges.get_available(), 3)


func test_max_decrease_drops_spent_timers_first() -> void:
	var charges := _make(3, 5.0)
	charges.try_consume()
	charges.set_max_charges(2)
	assert_eq(charges.get_available(), 1)


func test_next_charge_progress_tracks_the_soonest_charge() -> void:
	var charges := _make(2, 4.0)
	assert_eq(charges.get_next_charge_progress(), 1.0, "full charges report done")
	charges.try_consume()
	charges.tick(1.0)
	assert_almost_eq(charges.get_next_charge_progress(), 0.25, 0.001)
	charges.try_consume()
	charges.tick(1.0)
	# First charge is 2s in (progress 0.5); the fresher one is 1s in (0.25).
	assert_almost_eq(charges.get_next_charge_progress(), 0.5, 0.001)


func test_refill_restores_everything() -> void:
	var charges := _make()
	charges.try_consume()
	charges.try_consume()
	charges.refill()
	assert_eq(charges.get_available(), 2)
