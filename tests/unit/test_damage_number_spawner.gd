extends GutTest
## The spawner that turns EventBus.damage_dealt into a pooled DamageNumber.

var _spawner: DamageNumberSpawner
var _target: Node3D
var _original_setting: bool


func before_each() -> void:
	_original_setting = bool(SettingsManager.get_value("hud/damage_numbers", true))
	SettingsManager.set_value("hud/damage_numbers", true)
	_spawner = DamageNumberSpawner.new()
	_spawner.damage_number_scene = load("res://scenes/vfx/damage_number.tscn")
	add_child_autofree(_spawner)
	_target = add_child_autofree(Node3D.new())
	_target.global_position = Vector3(5, 0, 5)


func after_each() -> void:
	SettingsManager.set_value("hud/damage_numbers", _original_setting)


func test_a_hit_spawns_exactly_one_number() -> void:
	EventBus.damage_dealt.emit(_target, 15.0, false)
	assert_eq(_spawner.get_live_count(), 1)


func test_zero_damage_spawns_nothing() -> void:
	EventBus.damage_dealt.emit(_target, 0.0, false)
	assert_eq(_spawner.get_live_count(), 0)


func test_turning_damage_numbers_off_spawns_nothing() -> void:
	SettingsManager.set_value("hud/damage_numbers", false)
	EventBus.damage_dealt.emit(_target, 15.0, false)
	assert_eq(_spawner.get_live_count(), 0)


func test_the_number_spawns_above_the_targets_position() -> void:
	EventBus.damage_dealt.emit(_target, 15.0, false)
	var number: Node3D = _spawner._live[0]
	assert_almost_eq(number.global_position.x, _target.global_position.x, 0.2)
	assert_gt(number.global_position.y, _target.global_position.y,
		"the number must float above the target's own origin")


func test_a_target_with_no_3d_position_is_ignored_without_erroring() -> void:
	var flat_target := Node.new()
	add_child_autofree(flat_target)
	EventBus.damage_dealt.emit(flat_target, 15.0, false)
	assert_eq(_spawner.get_live_count(), 0)


# ------------------------------------------------- pool dedicado

## El anillo se arma una vez y nunca crece: pedir numeros no instancia nada.
func test_the_pool_is_built_once_at_the_cap() -> void:
	assert_eq(_spawner.get_pool_size(), _spawner.max_live_numbers)
	var children_before: int = _spawner.get_child_count()
	for i: int in _spawner.max_live_numbers * 3:
		var target: Node3D = add_child_autofree(Node3D.new())
		target.global_position = Vector3(float(i) * 3.0, 0.0, 0.0)
		EventBus.damage_dealt.emit(target, 10.0, false)
	assert_eq(_spawner.get_child_count(), children_before, "ningun numero nuevo")


## Un numero que termino vuelve al anillo y queda oculto, sin salir del arbol.
func test_a_finished_number_goes_back_hidden() -> void:
	EventBus.damage_dealt.emit(_target, 15.0, false)
	var number: DamageNumber = _spawner._live[0]
	assert_true(number.visible)

	await wait_seconds(DamageNumber.LIFETIME + 0.2)
	assert_eq(_spawner.get_live_count(), 0)
	assert_false(number.visible, "libre es oculto")
	assert_true(number.is_inside_tree(), "y sigue en el arbol, listo para reusar")


## Un numero reciclado para otro enemigo no puede recibir el daño del primero:
## la entrada abierta guarda el play_id y deja de valer cuando el numero cambia
## de dueño.
func test_a_recycled_number_does_not_take_the_old_targets_hits() -> void:
	_spawner.max_live_numbers = 1
	for child: Node in _spawner.get_children():
		child.free()
	_spawner._free.clear()
	_spawner._live.clear()
	_spawner._build_pool()

	var other: Node3D = add_child_autofree(Node3D.new())
	EventBus.damage_dealt.emit(_target, 30.0, false)
	# El unico numero se libera y lo toma la plata de una kill sobre otro cuerpo.
	EventBus.kill_payout.emit(10, [], 0, other.global_position)
	EventBus.damage_dealt.emit(_target, 20.0, false)

	var number: DamageNumber = _spawner._live[0]
	assert_eq(number.get_node("Label3D").text, "+$10",
		"el numero de la kill no puede sumar el daño del enemigo anterior")


# ------------------------------------------------- presupuesto

## Las dos reglas que sacaron el costo de los numeros de daño, medido con
## tools/profile_damage_numbers.gd: sumar golpes al mismo objetivo, y topear
## cuantos numeros hay en pantalla.

func test_two_quick_hits_on_the_same_target_share_one_number() -> void:
	EventBus.damage_dealt.emit(_target, 30.0, false)
	EventBus.damage_dealt.emit(_target, 20.0, false)

	assert_eq(_spawner.get_live_count(), 1,
		"una escopeta son ocho impactos en el mismo frame, no ocho numeros")


func test_the_merged_number_shows_the_total() -> void:
	EventBus.damage_dealt.emit(_target, 30.0, false)
	EventBus.damage_dealt.emit(_target, 20.0, false)
	await wait_physics_frames(1)

	var number: DamageNumber = _spawner._live[0]
	assert_eq(number.get_node("Label3D").text, "50",
		"un 50 dice mas que un 30 y un 20 superpuestos")


func test_separate_targets_get_their_own_numbers() -> void:
	var other: Node3D = add_child_autofree(Node3D.new())
	other.global_position = Vector3(-8, 0, -8)
	EventBus.damage_dealt.emit(_target, 30.0, false)
	EventBus.damage_dealt.emit(other, 30.0, false)

	assert_eq(_spawner.get_live_count(), 2, "cada enemigo tiene su numero")


## El tope es lo unico que realmente movio la medicion. Doce numeros ya son mas
## de los que alguien puede leer, asi que el trece no informa y si cuesta.
func test_the_number_of_live_numbers_is_capped() -> void:
	for i: int in _spawner.max_live_numbers + 6:
		var target: Node3D = add_child_autofree(Node3D.new())
		target.global_position = Vector3(float(i) * 3.0, 0.0, 0.0)
		EventBus.damage_dealt.emit(target, 10.0, false)

	assert_eq(_spawner.get_live_count(), _spawner.max_live_numbers,
		"pasado el tope el golpe sigue existiendo, solo no pinta un Label3D mas")


## La plata de una kill entra aunque el anillo este lleno: se libera el mas viejo.
func test_a_kill_payout_gets_in_even_when_full() -> void:
	for i: int in _spawner.max_live_numbers:
		var target: Node3D = add_child_autofree(Node3D.new())
		target.global_position = Vector3(float(i) * 3.0, 0.0, 0.0)
		EventBus.damage_dealt.emit(target, 10.0, false)
	EventBus.kill_payout.emit(25, [], 5, Vector3.ZERO)

	assert_eq(_spawner.get_live_count(), _spawner.max_live_numbers)
	var newest: DamageNumber = _spawner._live[-1]
	assert_eq(newest.get_node("Label3D").text, "+$30")
