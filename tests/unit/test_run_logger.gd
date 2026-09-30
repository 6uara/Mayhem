extends GutTest
## The playtest log: what a run did, written where a playtester can send it.

const TEST_DIR: String = "user://test_runs"

var _logger: RunLogger


func before_each() -> void:
	_clear_dir()
	_logger = RunLogger.new()
	_logger.log_dir = TEST_DIR
	add_child_autofree(_logger)


func after_each() -> void:
	_clear_dir()


func _clear_dir() -> void:
	var dir: String = ProjectSettings.globalize_path(TEST_DIR)
	if not DirAccess.dir_exists_absolute(dir):
		return
	for file: String in DirAccess.get_files_at(TEST_DIR):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)


func _wave(par: float) -> WaveData:
	var wave := WaveData.new()
	wave.par_time = par
	return wave


func test_a_run_is_written_with_its_waves_kills_and_purchases() -> void:
	EventBus.wave_started.emit(0, _wave(40.0))
	EventBus.kill_scored.emit(&"rusher", Vector3.ZERO, true, 10)
	EventBus.kill_scored.emit(&"rusher", Vector3.ZERO, false, 10)
	EventBus.weapon_fired.emit(&"pistol")
	EventBus.wave_completed.emit(0, 31.5, 12.0)
	EventBus.purchase_made.emit(&"damage", 150)
	EventBus.wave_started.emit(1, _wave(52.0))
	EventBus.player_damaged.emit(25.0, 50.0)
	EventBus.run_finished.emit(1234, 80.0, 1, false)

	var files: PackedStringArray = DirAccess.get_files_at(TEST_DIR)
	assert_eq(files.size(), 1, "one file per run")
	if files.is_empty():
		return
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(TEST_DIR.path_join(files[0])))
	assert_true(parsed is Dictionary)
	var run: Dictionary = parsed
	var waves: Array = run["waves"]
	assert_eq(waves.size(), 2)
	assert_eq(int((waves[0] as Dictionary)["kills"]["rusher"]), 2)
	assert_eq(int((waves[0] as Dictionary)["headshots"]), 1)
	assert_true(bool((waves[0] as Dictionary)["cleared"]))
	assert_false(bool((waves[1] as Dictionary)["cleared"]), "died in the second one")
	assert_eq(float((waves[1] as Dictionary)["damage_taken"]), 25.0)
	assert_eq(int(run["died_in_wave"]), 1)
	assert_eq((run["purchases"] as Array).size(), 1)
	assert_eq(int(run["shots"]["pistol"]), 1)


func test_only_the_newest_runs_are_kept() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))
	for index: int in RunLogger.MAX_LOGS + 3:
		var file: FileAccess = FileAccess.open(
			TEST_DIR.path_join("run_2000-01-01_00-00-%02d.json" % index), FileAccess.WRITE)
		file.store_string("{}")
		file.close()
	EventBus.wave_started.emit(0, _wave(40.0))
	EventBus.run_finished.emit(0, 10.0, 0, false)
	var files: PackedStringArray = DirAccess.get_files_at(TEST_DIR)
	assert_eq(files.size(), RunLogger.MAX_LOGS)
	assert_false(files.has("run_2000-01-01_00-00-00.json"), "the oldest went first")
