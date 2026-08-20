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
	ObjectPool.clear()


func after_each() -> void:
	SettingsManager.set_value("hud/damage_numbers", _original_setting)
	ObjectPool.clear()


func test_a_hit_spawns_exactly_one_number() -> void:
	EventBus.damage_dealt.emit(_target, 15.0, false)
	assert_eq(ObjectPool.get_active_count(), 1)


func test_zero_damage_spawns_nothing() -> void:
	EventBus.damage_dealt.emit(_target, 0.0, false)
	assert_eq(ObjectPool.get_active_count(), 0)


func test_turning_damage_numbers_off_spawns_nothing() -> void:
	SettingsManager.set_value("hud/damage_numbers", false)
	EventBus.damage_dealt.emit(_target, 15.0, false)
	assert_eq(ObjectPool.get_active_count(), 0)


func test_the_number_spawns_above_the_targets_position() -> void:
	EventBus.damage_dealt.emit(_target, 15.0, false)
	var number: Node3D = ObjectPool._in_use.keys()[0]
	assert_almost_eq(number.global_position.x, _target.global_position.x, 0.2)
	assert_gt(number.global_position.y, _target.global_position.y,
		"the number must float above the target's own origin")


func test_a_target_with_no_3d_position_is_ignored_without_erroring() -> void:
	var flat_target := Node.new()
	add_child_autofree(flat_target)
	EventBus.damage_dealt.emit(flat_target, 15.0, false)
	assert_eq(ObjectPool.get_active_count(), 0)


# ------------------------------------------------- presupuesto

## Las dos reglas que sacaron el costo de los numeros de daño, medido con
## tools/profile_damage_numbers.gd: sumar golpes al mismo objetivo, y topear
## cuantos numeros hay en pantalla.

func test_two_quick_hits_on_the_same_target_share_one_number() -> void:
	EventBus.damage_dealt.emit(_target, 30.0, false)
	EventBus.damage_dealt.emit(_target, 20.0, false)

	assert_eq(ObjectPool.get_active_count(), 1,
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

	assert_eq(ObjectPool.get_active_count(), 2, "cada enemigo tiene su numero")


## El tope es lo unico que realmente movio la medicion. Doce numeros ya son mas
## de los que alguien puede leer, asi que el trece no informa y si cuesta.
func test_the_number_of_live_numbers_is_capped() -> void:
	var targets: Array[Node3D] = []
	for i: int in _spawner.max_live_numbers + 6:
		var target: Node3D = add_child_autofree(Node3D.new())
		target.global_position = Vector3(float(i) * 3.0, 0.0, 0.0)
		targets.append(target)
		EventBus.damage_dealt.emit(target, 10.0, false)

	assert_eq(ObjectPool.get_active_count(), _spawner.max_live_numbers,
		"pasado el tope el golpe sigue existiendo, solo no pinta un Label3D mas")
