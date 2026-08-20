extends GutTest
## Los dos esquemas de gadget que pidio el playtest: quick cast (apretar y sale)
## y equipar (apretar lo pone en la mano, el disparo lo lanza).
##
## Se prueba por handle_input y no llamando a throw() a mano, porque lo que
## cambia entre un modo y el otro es exactamente que hace cada tecla.

var _utility: UtilityComponent
var _aim: Node3D


func before_each() -> void:
	_aim = add_child_autofree(Node3D.new())
	_utility = UtilityComponent.new()
	_utility.aim_node = _aim
	var data := UtilityData.new()
	data.id = &"test_gadget"
	data.cooldown = 1.0
	data.max_carried = 3
	# Una escena de verdad: can_throw() rechaza un slot sin ella, y un slot que
	# no se puede lanzar no distingue un modo del otro.
	data.scene = load("res://scenes/utilities/stun_grenade.tscn")
	_utility.slots = [data, null, null] as Array[UtilityData]
	add_child_autofree(_utility)
	await wait_physics_frames(1)
	_utility.add_charge(&"test_gadget", 2)


func after_each() -> void:
	SettingsManager.set_value(UtilityComponent.QUICK_CAST_KEY, true)
	ObjectPool.release_all()


func _press(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _set_quick_cast(enabled: bool) -> void:
	SettingsManager.set_value(UtilityComponent.QUICK_CAST_KEY, enabled)


# ------------------------------------------------- quick cast

func test_quick_cast_never_leaves_anything_in_the_hand() -> void:
	_set_quick_cast(true)
	_utility.handle_input(_press(&"utility_1"))
	assert_eq(_utility.armed_slot, -1, "en quick cast el gadget sale, no se equipa")


func test_quick_cast_consumes_a_charge_on_the_key_press() -> void:
	_set_quick_cast(true)
	var before: int = _utility.get_carried(0)
	_utility.handle_input(_press(&"utility_1"))
	assert_eq(_utility.get_carried(0), before - 1, "apretar es lanzar")


# ------------------------------------------------- equipar y lanzar

func test_the_key_arms_instead_of_throwing() -> void:
	_set_quick_cast(false)
	var before: int = _utility.get_carried(0)
	_utility.handle_input(_press(&"utility_1"))

	assert_eq(_utility.armed_slot, 0, "queda en la mano")
	assert_eq(_utility.get_carried(0), before, "equipar no gasta nada")


func test_fire_throws_what_is_armed() -> void:
	_set_quick_cast(false)
	var before: int = _utility.get_carried(0)
	_utility.handle_input(_press(&"utility_1"))
	var handled: bool = _utility.handle_input(_press(&"fire"))

	assert_true(handled, "el disparo se consume aca, el arma no dispara tambien")
	assert_eq(_utility.armed_slot, -1, "ya no queda nada en la mano")
	assert_eq(_utility.get_carried(0), before - 1, "recien ahora se gasta la carga")


## Equipar por error tiene que tener salida, o es un estado del que no se sale.
func test_the_same_key_puts_it_away() -> void:
	_set_quick_cast(false)
	_utility.handle_input(_press(&"utility_1"))
	_utility.handle_input(_press(&"utility_1"))

	assert_eq(_utility.armed_slot, -1, "la misma tecla lo guarda")
	assert_eq(_utility.get_carried(0), 2, "guardarlo no cuesta una carga")


func test_fire_is_left_alone_when_nothing_is_armed() -> void:
	_set_quick_cast(false)
	assert_false(_utility.handle_input(_press(&"fire")),
		"sin gadget en la mano el disparo es del arma")


func test_an_empty_slot_cannot_be_armed() -> void:
	_set_quick_cast(false)
	_utility.reset()
	_utility.handle_input(_press(&"utility_1"))
	assert_eq(_utility.armed_slot, -1, "no se equipa lo que no se tiene")


## Volver de la pausa con algo cargado que no recordas es peor que perder el
## equipado.
func test_pausing_puts_the_gadget_away() -> void:
	_set_quick_cast(false)
	_utility.handle_input(_press(&"utility_1"))
	EventBus.game_paused.emit(true)
	await wait_physics_frames(1)
	assert_eq(_utility.armed_slot, -1, "la pausa lo guarda")
