extends GutTest
## The dev console's command layer, driven through `execute()` with no UI.


func before_each() -> void:
	UpgradeManager.reset()


func after_all() -> void:
	UpgradeManager.reset()
	EconomyManager.reset()


func test_unknown_commands_say_so_instead_of_crashing() -> void:
	assert_string_contains(DevConsole.execute("frobnicate"), "unknown command")


func test_blank_input_is_ignored() -> void:
	assert_eq(DevConsole.execute("   "), "")


func test_help_lists_every_command() -> void:
	var output: String = DevConsole.execute("help")
	assert_string_contains(output, "give")
	assert_string_contains(output, "kill_all")


func test_help_explains_one_command() -> void:
	assert_string_contains(DevConsole.execute("help give"), "Add currency")


func test_give_adds_currency() -> void:
	var before: int = EconomyManager.currency
	DevConsole.execute("give 250")
	assert_eq(EconomyManager.currency, before + 250)


func test_commands_are_case_insensitive() -> void:
	var before: int = EconomyManager.currency
	DevConsole.execute("GIVE 10")
	assert_eq(EconomyManager.currency, before + 10)


func test_upgrade_reports_a_missing_id_rather_than_erroring() -> void:
	assert_string_contains(DevConsole.execute("upgrade not_a_real_upgrade"), "no upgrade at")


func test_upgrade_grants_a_global_upgrade() -> void:
	DevConsole.execute("upgrade move_speed")
	assert_true(UpgradeManager.has_upgrade(&"move_speed"))


func test_upgrades_lists_what_is_owned() -> void:
	assert_string_contains(DevConsole.execute("upgrades"), "no bonuses")
	DevConsole.execute("upgrade move_speed")
	assert_string_contains(DevConsole.execute("upgrades"), "move_speed")


func test_clear_upgrades_drops_everything() -> void:
	DevConsole.execute("upgrade move_speed")
	DevConsole.execute("clear_upgrades")
	assert_eq(UpgradeManager.get_owned_entries().size(), 0)


func test_timescale_is_clamped_to_something_survivable() -> void:
	DevConsole.execute("timescale 99")
	assert_eq(Engine.time_scale, 8.0)
	DevConsole.execute("timescale 1")
	assert_eq(Engine.time_scale, 1.0)


func test_commands_that_need_a_player_report_its_absence() -> void:
	assert_string_contains(DevConsole.execute("heal"), "no player")
	assert_string_contains(DevConsole.execute("tp 0 0 0"), "no player")
