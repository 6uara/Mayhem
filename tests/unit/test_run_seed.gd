extends GutTest
## La semilla de la run y el codigo para compartirla.
##
## Lo que se fija: que la misma semilla da las mismas corrientes, que cada
## sistema tiene la suya, y que un codigo que alguien copio de un mensaje se lee
## de vuelta igual - con los errores de tipeo que Crockford perdona.

var _saved_mode: GameManager.Mode
var _saved_weapon: StringName
var _saved_seed: int


func before_each() -> void:
	_saved_mode = GameManager.run_mode
	_saved_weapon = GameManager.run_weapon_id
	_saved_seed = GameManager.run_fixed_seed


func after_each() -> void:
	GameManager.set_run_mode(_saved_mode, _saved_weapon)
	GameManager.set_run_seed(_saved_seed)
	RunSeed.begin()


func test_the_same_seed_gives_the_same_draws() -> void:
	RunSeed.begin(123456)
	var first: Array[int] = []
	for _i: int in 5:
		first.append(RunSeed.rng(&"shop").randi())
	RunSeed.begin(123456)
	for i: int in 5:
		assert_eq(RunSeed.rng(&"shop").randi(), first[i])


## Comprar una mejora mas no puede mover donde cae el proximo regalo.
func test_each_system_draws_from_its_own_stream() -> void:
	RunSeed.begin(99)
	var drop_alone: int = RunSeed.rng(&"crowd_drops").randi()
	RunSeed.begin(99)
	for _i: int in 10:
		RunSeed.rng(&"shop").randi()
	assert_eq(RunSeed.rng(&"crowd_drops").randi(), drop_alone)


func test_a_fresh_run_gets_a_fresh_valid_seed() -> void:
	RunSeed.begin()
	assert_gt(RunSeed.run_seed, 0)
	assert_lte(RunSeed.run_seed, RunSeed.MAX_SEED)


func test_a_seed_survives_its_text() -> void:
	for seed_value: int in [1, 31, 32, 987654321, RunSeed.MAX_SEED]:
		var text: String = RunSeed.encode_seed(seed_value)
		assert_eq(text.length(), 9, "ocho caracteres y un guion: %s" % text)
		assert_eq(RunSeed.decode_seed(text), seed_value)


func test_typos_crockford_forgives_are_forgiven() -> void:
	var text: String = RunSeed.encode_seed(RunSeed.decode_seed("0011-ABCD"))
	assert_eq(RunSeed.decode_seed("oo1l-abcd"), RunSeed.decode_seed(text))


func test_garbage_is_not_a_seed() -> void:
	assert_eq(RunSeed.decode_seed(""), 0)
	assert_eq(RunSeed.decode_seed("ABC"), 0)
	assert_eq(RunSeed.decode_seed("UUUU-UUUU"), 0, "la U no esta en el alfabeto")
	assert_true(RunSeed.parse_code("hola").is_empty())


func test_an_arsenal_code_reads_back() -> void:
	var code: String = RunSeed.make_code(424242, GameManager.Mode.ARSENAL, &"")
	assert_true(code.begins_with("MAYHEM-ARSENAL-"), code)
	var parsed: Dictionary = RunSeed.parse_code(code)
	assert_eq(int(parsed["seed"]), 424242)
	assert_eq(int(parsed["mode"]), GameManager.Mode.ARSENAL)


## El id del rifle lleva guion bajo: no se puede confundir con un separador.
func test_a_one_gun_code_keeps_its_weapon() -> void:
	var code: String = RunSeed.make_code(7, GameManager.Mode.SINGLE_WEAPON, &"rifle_ak")
	assert_eq(code, "MAYHEM-RIFLE_AK-%s" % RunSeed.encode_seed(7))
	var parsed: Dictionary = RunSeed.parse_code(code.to_lower())
	assert_eq(int(parsed["mode"]), GameManager.Mode.SINGLE_WEAPON)
	assert_eq(StringName(parsed["weapon_id"]), &"rifle_ak")


func test_a_bare_seed_keeps_the_chosen_mode() -> void:
	var parsed: Dictionary = RunSeed.parse_code(RunSeed.encode_seed(55))
	assert_eq(int(parsed["seed"]), 55)
	assert_eq(int(parsed["mode"]), -1)


func test_the_mode_screen_takes_a_pasted_code() -> void:
	var select := ModeSelect.new()
	add_child_autofree(select)
	assert_true(select.apply_seed_text(
		RunSeed.make_code(31337, GameManager.Mode.SINGLE_WEAPON, &"shotgun")))
	assert_eq(GameManager.run_fixed_seed, 31337)
	assert_eq(select.get_mode(), GameManager.Mode.SINGLE_WEAPON)
	assert_eq(select.get_weapon_id(), &"shotgun")
	assert_true(select.apply_seed_text(""), "vacio es una run nueva")
	assert_eq(GameManager.run_fixed_seed, 0)
	assert_false(select.apply_seed_text("no es un codigo"))


func test_the_match_starts_from_the_fixed_seed() -> void:
	GameManager.set_run_seed(8080)
	RunSeed.begin(GameManager.run_fixed_seed)
	assert_eq(RunSeed.run_seed, 8080)
