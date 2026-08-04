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


func after_each() -> void:
	NarratorManager.clear_queue()


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
