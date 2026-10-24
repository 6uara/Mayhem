extends GutTest
## La presion de retirada y lo que el director hace con ella.
##
## Lo que importa probar es la forma de la respuesta, no los numeros: que solo
## cuente retroceder (no moverse de costado), que un paso atras no dispare nada,
## que se apague antes de lo que tarda en subir, y que todo lo que la horda
## contesta sea un grado y no un interruptor.

const FACING := Vector3(0.0, 0.0, -1.0)
const BACKWARD := Vector3(0.0, 0.0, 6.0)
const STRAFE := Vector3(6.0, 0.0, 0.0)

var _saved_wave: int = -1
var _target: Node3D


func before_each() -> void:
	_saved_wave = WaveManager.current_index
	CombatDirector.reset()


func after_each() -> void:
	WaveManager.current_index = _saved_wave
	CombatDirector.reset()
	if is_instance_valid(_target):
		_target.free()


func _pressure() -> RetreatPressure:
	return RetreatPressure.new(RetreatPressureConfig.new())


## El director con un jugador falso parado en el origen, mirando a -Z y
## retrocediendo a `velocity`, con la presion ya en `value`.
func _director_retreating(value: float, velocity: Vector3 = BACKWARD) -> void:
	_target = Node3D.new()
	CombatDirector._target = _target
	CombatDirector._target_position = Vector3.ZERO
	CombatDirector._target_facing = FACING
	CombatDirector._target_velocity = velocity
	CombatDirector.retreat.value = value
	WaveManager.current_index = 9


# La medicion

func test_only_the_backward_part_of_the_velocity_counts() -> void:
	assert_eq(RetreatPressure.backward_velocity(STRAFE, FACING), Vector3.ZERO,
		"de costado no es retroceder")
	assert_eq(RetreatPressure.backward_velocity(-BACKWARD, FACING), Vector3.ZERO,
		"hacia adelante tampoco")
	var diagonal: Vector3 = RetreatPressure.backward_velocity(BACKWARD + STRAFE, FACING)
	assert_almost_eq(diagonal.z, 6.0, 0.001, "en diagonal cuenta la parte de atras")
	assert_almost_eq(diagonal.x, 0.0, 0.001)


func test_sustained_retreat_builds_and_a_step_back_does_not() -> void:
	var pressure: RetreatPressure = _pressure()
	for i: int in 30:  # Medio segundo.
		pressure.update(BACKWARD, FACING, 1.0 / 60.0)
	assert_eq(pressure.effect(9), 0.0, "un paso atras para esquivar no es un patron")
	for i: int in 180:  # Tres segundos mas.
		pressure.update(BACKWARD, FACING, 1.0 / 60.0)
	assert_gt(pressure.effect(9), 0.5, "retroceder sostenido si")


func test_walking_slowly_backward_builds_nothing() -> void:
	var pressure: RetreatPressure = _pressure()
	for i: int in 600:
		pressure.update(Vector3(0.0, 0.0, 1.5), FACING, 1.0 / 60.0)
	assert_eq(pressure.value, 0.0)


func test_strafing_builds_nothing() -> void:
	var pressure: RetreatPressure = _pressure()
	for i: int in 600:
		pressure.update(STRAFE, FACING, 1.0 / 60.0)
	assert_eq(pressure.value, 0.0, "moverse de costado es la respuesta, no el problema")


## Cambiar de patron tiene que pagar enseguida: si bajara tan lento como sube, el
## jugador que ya corrigio seguiria recibiendo la respuesta.
func test_it_cools_down_faster_than_it_builds() -> void:
	var config := RetreatPressureConfig.new()
	assert_lt(config.fall_time, config.rise_time)
	var pressure := RetreatPressure.new(config)
	pressure.value = 1.0
	for i: int in int(config.fall_time * 60.0) + 1:
		pressure.update(STRAFE, FACING, 1.0 / 60.0)
	assert_eq(pressure.value, 0.0)


func test_the_first_waves_get_a_softer_answer() -> void:
	var pressure: RetreatPressure = _pressure()
	pressure.value = 1.0
	assert_lt(pressure.effect(0), pressure.effect(9))
	assert_gt(pressure.effect(0), 0.0, "suave, no apagado")
	assert_eq(pressure.effect(9), 1.0)


# Lo que contesta el director

func test_nothing_changes_while_nobody_retreats() -> void:
	_director_retreating(0.0)
	assert_eq(CombatDirector.retreat_lead(1.0), Vector3.ZERO)
	assert_eq(CombatDirector.door_weight(Vector3(0.0, 0.0, 30.0)), 1.0)


func test_shots_lead_only_the_retreat() -> void:
	_director_retreating(1.0, BACKWARD + STRAFE)
	var lead: Vector3 = CombatDirector.retreat_lead(1.0)
	assert_gt(lead.z, 0.0, "adelanta hacia donde retrocede")
	assert_almost_eq(lead.x, 0.0, 0.001, "y no hacia donde se corre de costado")


func test_doors_behind_the_retreat_weigh_more_but_none_drops_out() -> void:
	_director_retreating(1.0)
	var ahead: float = CombatDirector.door_weight(Vector3(0.0, 0.0, 30.0))
	var front: float = CombatDirector.door_weight(Vector3(0.0, 0.0, -30.0))
	assert_gt(ahead, front, "la puerta hacia donde va pesa mas")
	assert_eq(front, 1.0, "la de enfrente sigue igual, nunca menos")


func test_only_the_melee_pursue_faster() -> void:
	_director_retreating(1.0)
	var rusher := Enemy.new()
	rusher.data = load("res://data/enemies/rusher.tres")
	var ranger := Enemy.new()
	ranger.data = load("res://data/enemies/ranger.tres")
	assert_gt(CombatDirector.pursuit_multiplier(rusher), 1.0)
	assert_lte(CombatDirector.pursuit_multiplier(rusher),
		1.0 + CombatDirector.retreat.config.pursuit_speed_bonus, "con tope")
	assert_eq(CombatDirector.pursuit_multiplier(ranger), 1.0)
	rusher.free()
	ranger.free()


# Caminar hacia atras

func test_walking_backward_is_slower_and_strafing_is_not() -> void:
	var movement := MovementComponent.new()
	var body := CharacterBody3D.new()
	movement.body = body
	# Sin girar, el cuerpo mira a -Z: +Z es su espalda.
	assert_almost_eq(movement.backpedal_factor(Vector3(0.0, 0.0, 1.0)),
		movement.backpedal_speed_multiplier, 0.001)
	assert_eq(movement.backpedal_factor(Vector3(1.0, 0.0, 0.0)), 1.0, "de costado no cobra")
	assert_eq(movement.backpedal_factor(Vector3(0.0, 0.0, -1.0)), 1.0)
	var diagonal: float = movement.backpedal_factor(Vector3(1.0, 0.0, 1.0).normalized())
	assert_between(diagonal, movement.backpedal_speed_multiplier, 1.0)
	movement.free()
	body.free()
