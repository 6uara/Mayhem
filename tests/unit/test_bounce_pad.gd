extends GutTest
## BouncePad had no test coverage before this. The default velocity used to leave
## only 0.12m of clearance over the mid platforms under the player's own gravity -
## the kind of margin that reads as "the pad doesn't reach" the moment a frame is
## dropped or the platform is touched at an angle.

const PLAYER_GRAVITY: float = 24.0
const MID_PLATFORM_HEIGHT: float = 3.4
const HIGH_LEVEL_HEIGHT: float = 6.4
## Minimum comfortable clearance past the platform a pad targets.
const MIN_MARGIN: float = 0.5

var _pad: BouncePad
var _body: CharacterBody3D


func before_each() -> void:
	_pad = add_child_autofree(load("res://scenes/arena/bounce_pad.tscn").instantiate())
	_body = CharacterBody3D.new()
	_body.add_to_group(&"player")
	add_child_autofree(_body)


func _apex(velocity: float) -> float:
	return (velocity * velocity) / (2.0 * PLAYER_GRAVITY)


func test_default_pad_clears_the_mid_platform_with_margin() -> void:
	var apex: float = _apex(_pad.bounce_velocity)
	assert_gt(apex, MID_PLATFORM_HEIGHT + MIN_MARGIN,
		"default bounce_velocity %0.1f gives a %0.2fm apex against a %0.1fm platform"
			% [_pad.bounce_velocity, apex, MID_PLATFORM_HEIGHT])


## A fast arrival must stay fast - a pad may never quietly cap incoming velocity.
func test_preserve_higher_velocity_never_reduces_a_fast_arrival() -> void:
	_pad.bounce_velocity = 15.0
	_body.velocity.y = 40.0
	_pad._on_body_entered(_body)
	assert_almost_eq(_body.velocity.y, 40.0, 0.01,
		"an incoming velocity faster than the pad must not be slowed down")


func test_a_slow_arrival_is_launched_at_the_pad_velocity() -> void:
	_pad.bounce_velocity = 15.0
	_body.velocity.y = 1.0
	_pad._on_body_entered(_body)
	assert_almost_eq(_body.velocity.y, 15.0, 0.01)


func test_a_non_player_body_is_ignored() -> void:
	var stray := CharacterBody3D.new()
	add_child_autofree(stray)
	stray.velocity.y = 0.0
	_pad._on_body_entered(stray)
	assert_almost_eq(stray.velocity.y, 0.0, 0.01, "only the player group may bounce")
