extends GutTest
## GrappleComponent had zero test coverage before this - these guard the exact
## playtest report that finally forced it: aiming at an anchor and firing felt
## like a small hop instead of a swing.

var _body: CharacterBody3D
var _grapple: GrappleComponent


func before_each() -> void:
	_body = CharacterBody3D.new()
	add_child_autofree(_body)
	_grapple = GrappleComponent.new()
	_grapple.body = _body
	add_child_autofree(_grapple)
	await wait_frames(1)


## should_release() used to run the "moving away from the anchor" check on the same
## physics frame try_fire() succeeded - before the pull had touched velocity even
## once. Firing while carrying velocity with any component away from the anchor
## (backpedaling, strafing, residual momentum from a slide) made it true instantly,
## and all that played out was the release's small upward kick: a hop, not a swing.
func test_a_fresh_grapple_survives_moving_away_within_the_grace_window() -> void:
	_body.global_position = Vector3.ZERO
	_grapple._anchor = Vector3(10, 0, 0)
	_grapple.is_grappling = true
	_grapple._fired_at_msec = Time.get_ticks_msec()
	# Moving directly away from the anchor - the exact shape of the old bug.
	_body.velocity = Vector3(-5, 0, 0)

	assert_false(_grapple.should_release(),
		"a grapple must not end before the pull has had a chance to act")


## Distance is a real arrival, not a false positive - that check must never wait.
func test_arriving_at_the_anchor_releases_immediately_even_within_the_grace_window() -> void:
	_grapple._anchor = Vector3(1.0, 0, 0)
	_body.global_position = Vector3.ZERO
	_grapple.is_grappling = true
	_grapple._fired_at_msec = Time.get_ticks_msec()
	_body.velocity = Vector3.ZERO

	assert_true(_grapple.should_release(),
		"being inside arrive_distance must release regardless of timing")


## The grace window is a delay, not a waiver - a swing that is still departing once
## the pull has had its say must end.
func test_departure_still_releases_once_the_grace_window_has_passed() -> void:
	_body.global_position = Vector3.ZERO
	_grapple._anchor = Vector3(10, 0, 0)
	_grapple.is_grappling = true
	_grapple._fired_at_msec = Time.get_ticks_msec() - int(_grapple.min_flight_time * 1000.0) - 50
	_body.velocity = Vector3(-5, 0, 0)

	assert_true(_grapple.should_release(),
		"a grapple that is still moving away after the grace window must end")


func test_should_release_is_true_when_not_grappling() -> void:
	_grapple.is_grappling = false
	assert_true(_grapple.should_release())
