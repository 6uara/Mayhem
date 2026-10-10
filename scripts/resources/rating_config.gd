@tool
class_name RatingConfig
extends Resource
## Los numeros del rating de la transmision. Ver BroadcastRating.

## Puntos de rating por cada bono de estilo de una kill, antes de amplificar.
@export var gain_per_bonus: float = 4.0
## Cuanto amplifica la velocidad: a `bhop_max_speed` la ganancia se multiplica
## por 1 + esto. Quieto, no amplifica nada.
@export var speed_amplifier: float = 1.0
## Cuanto amplifica el ritmo: por cada kill reciente (hasta `pace_cap`) la
## ganancia sube esta fraccion.
@export var pace_per_kill: float = 0.15
@export var pace_cap: int = 5
## Ventana, en segundos, en la que una kill cuenta como reciente.
@export var pace_window: float = 4.0
## Lo que baja el rating una kill sin ningun estilo. Es lo que hace que una
## oleada de kills planas lo tire abajo aunque antes estuviera alto.
@export var plain_kill_drop: float = 3.0
## Lo que se enfria por segundo de pelea, haga lo que haga el jugador.
@export var decay_per_second: float = 1.6
## Techo del multiplicador de estilo, con el rating en 100.
@export var max_multiplier: float = 2.0
## Cuanto acorta el intervalo entre regalos del publico, con el rating en 100.
@export_range(0.0, 0.9) var max_drop_speedup: float = 0.4
## Escalones con nombre, de abajo hacia arriba. El primero es el piso.
@export var tier_thresholds: PackedFloat32Array = PackedFloat32Array([0.0, 25.0, 50.0, 80.0])
@export var tier_names: PackedStringArray = PackedStringArray(
	["OFF AIR", "LOCAL", "PRIME TIME", "MAYHEM"])
