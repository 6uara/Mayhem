extends GutTest
## The Host's commentary: the catalogue, and the events that reach it.
##
## The failure this guards against is not a crash. Before the catalogue existed the
## game shipped two lines, hardcoded inside the wave sequencer, and nothing anywhere
## reported that the rest of the system - tiers, cooldowns, the subtitle box, the
## broadcast bug, the punchline budget - was wired to almost no content. A Host with
## nothing to say fails silently, and silence is hard to notice in a test suite.

const CATALOG_PATH: String = "res://data/host/host_catalog.tres"

## Every occasion HostDirector can name. If one of these is missing from the
## catalogue the event fires into nothing and the Host just never mentions it.
const REQUIRED: Array[StringName] = [
	&"wave_start", &"wave_cleared", &"first_blood", &"streak", &"elite_wave",
	&"low_health", &"no_damage", &"too_slow", &"purchase", &"death", &"match_won",
]

var _catalog: HostCatalog


func before_all() -> void:
	_catalog = load(CATALOG_PATH)


func before_each() -> void:
	# NarratorManager is a real singleton, not recreated per test - its pacing
	# state (line/category cooldowns, the "don't speak too often" timer) would
	# otherwise leak between tests and make whichever one runs second flaky
	# depending on run order and how recently something else in the suite
	# called say().
	NarratorManager._since_last_line = NarratorManager.LINE_COOLDOWN
	NarratorManager._line_cooldowns.clear()
	NarratorManager._category_cooldowns.clear()
	NarratorManager._category_overrides.clear()
	# A previous test's line may still be "playing" (is_speaking) if that test
	# didn't await its full duration before returning - request_line() would
	# otherwise queue behind it instead of playing immediately.
	NarratorManager.is_speaking = false
	NarratorManager._current_priority = -1


func after_each() -> void:
	NarratorManager.clear_queue()
	NarratorManager.set_presenter(&"subtitles_only")


func test_the_catalogue_loads() -> void:
	assert_not_null(_catalog, "host catalogue exists at the path the manager reads")
	assert_gt(_catalog.sets.size(), 0, "and it has content")


func test_every_occasion_the_director_names_has_lines() -> void:
	for occasion: StringName in REQUIRED:
		var line_set: HostLineSet = _catalog.find(occasion)
		assert_not_null(line_set, "no line set for '%s'" % occasion)
		if line_set != null:
			assert_true(line_set.has_lines(), "'%s' has no lines" % occasion)


## One line per occasion means the Host repeats himself the second time a moment
## happens, and these moments happen ten times a run.
func test_recurring_occasions_have_more_than_one_line() -> void:
	for occasion: StringName in [&"wave_start", &"wave_cleared", &"streak", &"death"]:
		var line_set: HostLineSet = _catalog.find(occasion)
		if line_set == null:
			continue
		assert_gt(line_set.lines.size(), 1,
			"'%s' fires repeatedly and needs variety" % occasion)


func test_no_two_sets_claim_the_same_occasion() -> void:
	var seen: Array[StringName] = []
	for line_set: HostLineSet in _catalog.sets:
		if line_set == null:
			continue
		assert_false(seen.has(line_set.id), "'%s' is defined twice" % line_set.id)
		seen.push_back(line_set.id)


## Format placeholders are content, so a set whose lines take an argument has to
## take it in every line - otherwise picking the wrong one throws at runtime.
func test_formatted_sets_are_consistent() -> void:
	for occasion: StringName in [&"wave_start", &"wave_cleared"]:
		var line_set: HostLineSet = _catalog.find(occasion)
		if line_set == null:
			continue
		for line: String in line_set.lines:
			assert_true(line.contains("%d"),
				"'%s' is called with a wave number: \"%s\" ignores it" % [occasion, line])


# ------------------------------------------------------------------ behaviour

func test_saying_an_occasion_produces_a_subtitle() -> void:
	watch_signals(NarratorManager)
	NarratorManager.say(&"death")
	await wait_frames(3)
	assert_signal_emitted(NarratorManager, "subtitle_shown",
		"a named occasion has to reach the subtitle layer")


func test_an_unknown_occasion_is_ignored_rather_than_crashing() -> void:
	watch_signals(NarratorManager)
	NarratorManager.say(&"no_such_occasion_exists")
	await wait_frames(3)
	assert_signal_not_emitted(NarratorManager, "subtitle_shown")


## A set never plays the same line twice running - with 37 lines across the run,
## hearing one repeat immediately is what would make the Host feel canned.
func test_a_set_does_not_repeat_itself_back_to_back() -> void:
	var line_set: HostLineSet = _catalog.find(&"death")
	assert_gt(line_set.lines.size(), 1, "precondition: more than one line")

	var seen: Array[int] = []
	for _i: int in 12:
		seen.push_back(NarratorManager._pick_index(&"death", line_set.lines.size()))
	for i: int in range(1, seen.size()):
		assert_ne(seen[i], seen[i - 1], "picked the same line twice running")


# ------------------------------------------------------------- voice packs

## No presenter ships with recordings yet (see assets/audio/voice/ - empty by
## design, the shop this content belongs to is external recording), so this is
## also the default steady state, not a corner case.
func test_a_missing_recording_still_shows_the_subtitle() -> void:
	watch_signals(NarratorManager)
	NarratorManager.say(&"death")
	await wait_frames(3)
	var params: Array = get_signal_parameters(NarratorManager, "subtitle_shown", 0)
	assert_true(params[0] != "", "the subtitle still carries the line's text")


func test_switching_presenter_switches_the_audio_path() -> void:
	var subtitles_only: String = NarratorManager._voice_path(&"subtitles_only", &"death_01")
	var other: String = NarratorManager._voice_path(&"friend_a", &"death_01")
	assert_ne(subtitles_only, other)
	assert_eq(other, "res://assets/audio/voice/friend_a/death_01.ogg")


## Adding a presenter is authoring a HostPresenter resource, not editing
## NarratorManager - proven here by mutating the catalog NarratorManager
## already loaded rather than touching any of its code.
func test_adding_a_presenter_needs_no_code_change() -> void:
	var fake := HostPresenter.new()
	fake.id = &"test_new_presenter"
	fake.display_name = "Test Presenter"
	NarratorManager.presenter_catalog.presenters.push_back(fake)

	assert_true(NarratorManager.get_presenters().any(
		func(p: HostPresenter) -> bool: return p.id == &"test_new_presenter"))
	assert_eq(NarratorManager.find_presenter(&"test_new_presenter"), fake)

	NarratorManager.presenter_catalog.presenters.erase(fake)


func test_set_presenter_clears_the_voice_cache() -> void:
	NarratorManager._voice_cache[&"death_01"] = null
	NarratorManager.set_presenter(&"some_other_presenter")
	assert_false(NarratorManager._voice_cache.has(&"death_01"),
		"a stale cache entry from the old presenter must not survive the switch")


func test_setting_the_same_presenter_again_is_a_no_op() -> void:
	NarratorManager.set_presenter(&"subtitles_only")
	NarratorManager._voice_cache[&"death_01"] = null
	NarratorManager.set_presenter(&"subtitles_only")
	assert_true(NarratorManager._voice_cache.has(&"death_01"),
		"re-selecting the current presenter must not blow away the cache")
