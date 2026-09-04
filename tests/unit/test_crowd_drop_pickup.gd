extends GutTest
## El gadget que el publico tira a la arena.
##
## Lo que hay que sostener aca no es el vuelo -eso es `ThrownUtility` y ya tiene
## sus tests- sino las tres reglas propias: que levantarlo sea exactamente lo que
## hacia el shop, que con el slot lleno el objeto se quede donde esta, y que
## ninguno se quede para siempre en la arena.

const PICKUP_SCENE: String = "res://scenes/arena/crowd_drop_pickup.tscn"
const PLAYER_SCENE: String = "res://scenes/player/player.tscn"


func _pickup() -> CrowdDropPickup:
	var scene := load(PICKUP_SCENE) as PackedScene
	var pickup := scene.instantiate() as CrowdDropPickup
	add_child_autofree(pickup)
	return pickup


func _player() -> Player:
	var scene := load(PLAYER_SCENE) as PackedScene
	var player := scene.instantiate() as Player
	add_child_autofree(player)
	return player


func _stun_grenade() -> UtilityData:
	return load("res://data/utilities/stun_grenade.tres") as UtilityData


## Lo pone en el piso sin esperar el vuelo: `_activate()` es lo que
## `ThrownUtility` llama cuando el arco toca algo, y es donde arranca el pickup.
func _land(pickup: CrowdDropPickup, utility: UtilityData) -> void:
	pickup.data = utility
	pickup._activate()


func test_landing_turns_the_throw_into_something_you_can_take() -> void:
	var pickup: CrowdDropPickup = _pickup()
	assert_false(pickup.is_available, "en el aire todavia no se levanta")
	_land(pickup, _stun_grenade())
	assert_true(pickup.is_available)
	assert_almost_eq(pickup.get_time_left(), pickup.despawn_time, 0.01)


func test_taking_it_adds_a_charge_to_its_own_slot() -> void:
	# Es lo mismo que hacia el shop: cambia de donde sale el gadget, no que es.
	var player: Player = _player()
	var data: UtilityData = _stun_grenade()
	var slot: int = player.utility.find_slot(data.id)
	assert_gte(slot, 0, "el jugador tiene que tener slot para la granada")
	var pickup: CrowdDropPickup = _pickup()
	_land(pickup, data)

	assert_true(pickup.collect(player))
	assert_eq(player.utility.get_carried(slot), 1)
	assert_false(pickup.is_available, "levantado una vez, no se levanta dos")


func test_a_full_slot_leaves_it_on_the_ground() -> void:
	# La misma regla que la caja de municion: pasar por encima con las manos
	# llenas tiene que dejarlo ahi para cuando de verdad haga falta.
	var player: Player = _player()
	var data: UtilityData = _stun_grenade()
	var slot: int = player.utility.find_slot(data.id)
	for _i: int in data.max_carried:
		player.utility.add_charge(data.id)
	assert_eq(player.utility.get_carried(slot), data.max_carried)

	var pickup: CrowdDropPickup = _pickup()
	_land(pickup, data)
	assert_false(pickup.collect(player), "no hay lugar, no se lo lleva")
	assert_true(pickup.is_available, "y sigue estando ahi")


func test_it_cannot_be_taken_before_it_lands() -> void:
	var player: Player = _player()
	var data: UtilityData = _stun_grenade()
	var pickup: CrowdDropPickup = _pickup()
	pickup.throw_from_stands(Vector3(0.0, 20.0, 0.0), Vector3(1.0, 0.0, 0.0), data)
	assert_false(pickup.collect(player), "todavia esta volando")
	assert_eq(player.utility.get_carried(player.utility.find_slot(data.id)), 0)


func test_it_is_visible_while_it_falls_but_not_yet_takeable() -> void:
	# Las dos mitades tienen que separarse: se ve para poder correr adonde va a
	# caer, y el halo es lo que despues dice que ya se puede levantar.
	var data: UtilityData = _stun_grenade()
	var pickup: CrowdDropPickup = _pickup()
	pickup.throw_from_stands(Vector3(0.0, 20.0, 0.0), Vector3(1.0, 0.0, 0.0), data)
	assert_true(pickup.core.visible, "en el aire se tiene que ver")
	assert_false(pickup.halo.visible, "pero el anillo todavia no")
	pickup._activate()
	assert_true(pickup.halo.visible, "en el piso si")


func test_nobody_took_it_so_it_goes_away() -> void:
	var pickup: CrowdDropPickup = _pickup()
	var data: UtilityData = _stun_grenade()
	watch_signals(pickup)
	_land(pickup, data)
	pickup.despawn_time = 0.5
	pickup._life_left = 0.05
	pickup._process(0.1)
	assert_signal_emitted_with_parameters(pickup, "expired", [data.id])
	assert_false(pickup.is_available)


func test_the_arc_lands_where_it_was_aimed() -> void:
	# La cuenta vive en el objeto y no en quien tira, para que nadie resuelva el
	# arco con una gravedad que no es la que el objeto usa despues.
	var from := Vector3(20.0, 12.0, -5.0)
	var to := Vector3(-4.0, 1.0, 6.0)
	var flight: float = 1.7
	var velocity: Vector3 = CrowdDropPickup.arc_to(from, to, flight)
	var landing: Vector3 = from + velocity * flight \
		- Vector3.UP * (0.5 * ThrownUtility.get_gravity() * flight * flight)
	assert_almost_eq(landing.x, to.x, 0.01)
	assert_almost_eq(landing.y, to.y, 0.01)
	assert_almost_eq(landing.z, to.z, 0.01)


func test_the_core_wears_the_colour_of_what_it_is() -> void:
	# Tres gadgets que se ven iguales de lejos convierten el pickup en una
	# sorpresa, y la decision de si vale la pena cruzar la arena se toma antes de
	# llegar, no al llegar.
	var pickup: CrowdDropPickup = _pickup()
	var data: UtilityData = _stun_grenade()
	pickup.throw_from_stands(Vector3.ZERO, Vector3.UP, data)
	var material := pickup.core.material_override as StandardMaterial3D
	assert_not_null(material, "el nucleo se tiñe con el color del gadget")
	assert_eq(material.albedo_color, data.accent_color)


func test_the_three_gadgets_do_not_look_alike() -> void:
	var ids: PackedStringArray = ["stun_grenade", "temp_wall", "slow_field"]
	var seen: Array[Color] = []
	for id: String in ids:
		var data := load("res://data/utilities/%s.tres" % id) as UtilityData
		for other: Color in seen:
			# A ojo, y de lejos: dos colores a menos de esto son el mismo color.
			var distance: float = absf(data.accent_color.r - other.r) \
				+ absf(data.accent_color.g - other.g) + absf(data.accent_color.b - other.b)
			assert_gt(distance, 0.3, "%s se confunde con otro gadget" % id)
		seen.append(data.accent_color)
