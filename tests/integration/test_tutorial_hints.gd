extends GutTest
## TutorialHintManager: fires each first-time-mechanic hint once, queues rather
## than overlaps, persists "seen" through SaveManager, and reads the live-bound
## key for hints that name one.


func before_each() -> void:
	SaveManager.clear_tutorial_hints()
	_reset_queue()


func after_each() -> void:
	SaveManager.clear_tutorial_hints()
	_reset_queue()


func _reset_queue() -> void:
	TutorialHintManager._queue.clear()
	TutorialHintManager._current = null
	TutorialHintManager._time_left = 0.0


func test_each_hint_fires_only_the_first_time_its_mechanic_happens() -> void:
	assert_false(SaveManager.has_seen_hint(&"dash"))
	watch_signals(TutorialHintManager)

	EventBus.dash_used.emit(3)
	assert_signal_emit_count(TutorialHintManager, "hint_shown", 0,
		"queued, not yet shown - _process hasn't ticked")
	assert_true(SaveManager.has_seen_hint(&"dash"), "marked seen the moment it queues")

	EventBus.dash_used.emit(3)
	EventBus.dash_used.emit(3)
	assert_eq(TutorialHintManager._queue.size(), 1,
		"a mechanic that already fired must not queue a second hint")


func test_a_seen_hint_stays_seen_across_a_reload() -> void:
	SaveManager.mark_hint_seen(&"grapple")
	SaveManager.load_tutorial_hints()
	assert_true(SaveManager.has_seen_hint(&"grapple"),
		"a seen hint must survive a reload from disk")


func test_clearing_tutorial_hints_forgets_everything() -> void:
	SaveManager.mark_hint_seen(&"reload")
	SaveManager.clear_tutorial_hints()
	assert_false(SaveManager.has_seen_hint(&"reload"))


func test_hints_never_overlap_on_screen() -> void:
	watch_signals(TutorialHintManager)
	EventBus.dash_used.emit(3)
	EventBus.grapple_started.emit(Vector3.ZERO)
	EventBus.weapon_reloaded.emit(&"pistol")
	assert_eq(TutorialHintManager._queue.size(), 3, "all three queued")

	TutorialHintManager._try_show_next()
	assert_signal_emit_count(TutorialHintManager, "hint_shown", 1)
	assert_eq(TutorialHintManager._queue.size(), 2, "one taken off the queue to show")

	# A second hint must not appear while the first is still showing.
	TutorialHintManager._try_show_next()
	assert_signal_emit_count(TutorialHintManager, "hint_shown", 1,
		"a hint already showing must block the next one")

	TutorialHintManager._finish_current()
	assert_signal_emit_count(TutorialHintManager, "hint_hidden", 1)
	TutorialHintManager._try_show_next()
	assert_signal_emit_count(TutorialHintManager, "hint_shown", 2,
		"the next hint shows only after the first finished")


func test_a_hint_shows_the_currently_bound_key() -> void:
	watch_signals(TutorialHintManager)
	EventBus.dash_used.emit(3)
	TutorialHintManager._try_show_next()

	var params: Array = get_signal_parameters(TutorialHintManager, "hint_shown", 0)
	var shown_text: String = params[0]
	assert_false(shown_text.contains("{action}"), "the placeholder must be substituted")
	assert_true(shown_text.contains(OS.get_keycode_string(
		(InputMap.action_get_events(&"dash")[0] as InputEventKey).physical_keycode)),
		"the hint must name the actual bound key, not a hardcoded one")
