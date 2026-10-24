class_name RetreatPressure
extends RefCounted
## Cuanto viene retrocediendo el jugador: un numero de 0 a 1 que sube mientras
## camina hacia atras de donde mira y baja en cuanto deja de hacerlo.
##
## Aparte del director para poder probarlo sin enemigos ni arena: es pura cuenta
## sobre una velocidad y una mirada. Quien lo usa es CombatDirector, que le pasa el
## snapshot del jugador una vez por frame.

var config: RetreatPressureConfig
## La presion acumulada, de 0 a 1.
var value: float = 0.0


func _init(with_config: RetreatPressureConfig = null) -> void:
	config = with_config if with_config != null else RetreatPressureConfig.new()


## La parte de `velocity` que va hacia atras de `facing`, aplanada. Cero si el
## jugador va hacia adelante o de costado: lo que se mide es retroceder, no moverse.
static func backward_velocity(velocity: Vector3, facing: Vector3) -> Vector3:
	var flat_facing := Vector3(facing.x, 0.0, facing.z)
	if flat_facing.length_squared() < 0.001:
		return Vector3.ZERO
	flat_facing = flat_facing.normalized()
	var along: float = Vector3(velocity.x, 0.0, velocity.z).dot(flat_facing)
	return flat_facing * along if along < 0.0 else Vector3.ZERO


func update(velocity: Vector3, facing: Vector3, delta: float) -> float:
	var speed: float = backward_velocity(velocity, facing).length()
	if speed >= config.min_retreat_speed:
		var rate: float = clampf(inverse_lerp(config.min_retreat_speed,
			maxf(config.full_retreat_speed, config.min_retreat_speed + 0.01), speed), 0.0, 1.0)
		value += delta / maxf(config.rise_time, 0.01) * maxf(rate, 0.1)
	else:
		value -= delta / maxf(config.fall_time, 0.01)
	value = clampf(value, 0.0, 1.0)
	return value


## Cuanto contesta la horda, de 0 a 1: nada por debajo de `onset`, una curva suave
## hasta la presion completa, y recortado por la oleada.
func effect(wave_index: int) -> float:
	if value <= config.onset:
		return 0.0
	return smoothstep(config.onset, 1.0, value) * wave_strength(wave_index)


## `wave_index` es 0-based, como `WaveManager.current_index`. Antes de la primera
## oleada (-1) vale lo mismo que en la primera.
func wave_strength(wave_index: int) -> float:
	var span: int = maxi(config.full_strength_wave - 1, 1)
	var progress: float = clampf(float(maxi(wave_index, 0)) / float(span), 0.0, 1.0)
	return lerpf(config.first_wave_strength, 1.0, progress)


func reset() -> void:
	value = 0.0
