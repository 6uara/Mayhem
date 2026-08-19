extends GutTest
## The progress screen GameManager puts up while a scene is actually being read
## off disk. Exercised on its own here; the threaded load that drives it lives in
## GameManager and cannot be run under GUT without swapping out the test runner's
## own scene - see test_game_manager.gd for the same constraint.

var _loading: LoadingScreen


func before_each() -> void:
	_loading = add_child_autofree(
		load("res://scenes/ui/loading_screen.tscn").instantiate())
	await wait_physics_frames(1)


func test_starts_hidden() -> void:
	assert_false(_loading.visible,
		"nothing may cover the screen until a load is slow enough to need it")


func test_begin_puts_it_up_empty() -> void:
	_loading.begin()
	assert_true(_loading.visible)
	assert_eq(_loading.get_node("Root/Column/Bar").filled, 0)
	assert_eq(_loading.get_node("Root/Column/Percent").text, "0%")


func test_the_bar_catches_up_to_the_reported_progress() -> void:
	_loading.begin()
	_loading.set_progress(1.0)

	var bar: SegmentStrip = _loading.get_node("Root/Column/Bar")
	assert_eq(bar.filled, 0, "the bar eases rather than teleporting, so it starts where it was")

	# Long enough for the catch-up to cover the whole bar at BAR_CATCHUP_SPEED.
	for _i: int in 60:
		_loading._process(0.02)
	assert_eq(bar.filled, bar.count)


## ResourceLoader's reported progress is not guaranteed to only ever rise, and a
## bar that retreats tells the player the load is failing when it is not.
func test_progress_never_goes_backwards() -> void:
	_loading.begin()
	_loading.set_progress(0.8)
	_loading.set_progress(0.2)

	for _i: int in 60:
		_loading._process(0.02)

	var bar: SegmentStrip = _loading.get_node("Root/Column/Bar")
	assert_eq(bar.filled, int(round(0.8 * float(bar.count))))


func test_finish_takes_it_down() -> void:
	_loading.begin()
	_loading.set_progress(0.4)
	_loading.finish()
	assert_false(_loading.visible)


## A second load reuses the same node, so anything the previous one left behind
## would show up as a bar that starts part-full.
func test_beginning_again_resets_the_bar() -> void:
	_loading.begin()
	_loading.set_progress(1.0)
	for _i: int in 60:
		_loading._process(0.02)
	_loading.finish()

	_loading.begin()
	assert_eq(_loading.get_node("Root/Column/Bar").filled, 0)
	assert_eq(_loading.get_node("Root/Column/Percent").text, "0%")
