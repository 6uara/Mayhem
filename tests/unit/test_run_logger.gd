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


func _read_only_run() -> Dictionary:
	var files: PackedStringArray = DirAccess.get_files_at(TEST_DIR)
	assert_eq(files.size(), 1, "one file per run")
	if files.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(TEST_DIR.path_join(files[0])))
	return parsed if parsed is Dictionary else {}


## Lo que el playtest necesita para saber por que se murio: de que vino el daño,
## en cada ola y en total, y que fue lo ultimo que pego.
func test_damage_is_logged_by_where_it_came_from() -> void:
	EventBus.wave_started.emit(0, _wave(40.0))
	EventBus.player_hit.emit(20.0, &"ranger")
	EventBus.player_hit.emit(30.0, &"bomber")
	EventBus.player_died.emit()
	EventBus.run_finished.emit(100, 30.0, 0, false)
	var run: Dictionary = _read_only_run()
	assert_eq(float(run["damage_by_cause"]["ranger"]), 20.0)
	assert_eq(float((run["waves"][0] as Dictionary)["damage_by_cause"]["bomber"]), 30.0)
	assert_eq(String(run["killed_by"]), "bomber")
	assert_eq(String(run["seed"]), RunSeed.get_seed_text())


func test_a_victory_has_no_killer() -> void:
	EventBus.wave_started.emit(0, _wave(40.0))
	EventBus.player_hit.emit(20.0, &"ranger")
	EventBus.run_finished.emit(100, 30.0, 10, true)
	assert_eq(String(_read_only_run()["killed_by"]), "")


## Las raras que se ofrecen y no se compran, las reglas que se eligen sobre las
## que se dejan, los contratos y los pedidos del publico: el balance de los
## sistemas nuevos sale de aca.
func test_offers_rules_contracts_and_requests_are_logged() -> void:
	EventBus.wave_started.emit(0, _wave(40.0))
	EventBus.shop_offers_rolled.emit([{"id": &"damage", "rare": false},
		{"id": &"slug", "rare": true}])
	EventBus.broadcast_rules_offered.emit([&"manhunt", &"heavyweights"], &"grounded")
	EventBus.wave_completed.emit(0, 30.0, 0.0)
	EventBus.wave_started.emit(1, _wave(40.0))
	EventBus.broadcast_rule_started.emit(&"manhunt", "MANHUNT", "")
	EventBus.broadcast_contract_started.emit(&"grounded", "GROUNDED", "", 200)
	EventBus.crowd_request_ended.emit(&"spin", true)
	EventBus.broadcast_contract_settled.emit(&"grounded", 200)
	EventBus.run_finished.emit(100, 60.0, 2, false)
	var run: Dictionary = _read_only_run()
	var offer: Dictionary = (run["shop_offers"] as Array)[0]
	assert_true(bool((offer["offers"] as Array)[1]["rare"]))
	var wave: Dictionary = (run["waves"] as Array)[1]
	assert_eq(wave["rules_offered"], ["manhunt", "heavyweights", "contract:grounded"])
	assert_eq(String(wave["rule"]), "manhunt")
	assert_eq(String(wave["contract"]), "grounded")
	assert_eq(int(wave["contract_paid"]), 200)
	assert_true(bool((wave["crowd_requests"] as Array)[0]["success"]))
