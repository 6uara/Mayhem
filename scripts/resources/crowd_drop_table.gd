@tool
class_name CrowdDropTable
extends Resource
## Que tira el publico y cada cuanto.
##
## Es un recurso y no exports en la escena por la misma razon que `ShopCatalog`:
## los gadgets dejaron de comprarse, asi que esta tabla es ahora la unica fuente
## de utilidades del juego, y rebalancearla no puede obligar a abrir `game.tscn`.

## Lo que el publico puede tirar. Vacio, no tira nada.
@export var utilities: Array[UtilityData] = []
## Peso de cada entrada, en el mismo orden. Lo que falte cuenta como 1.0, asi que
## una tabla sin pesos reparte parejo.
@export var weights: PackedFloat32Array = PackedFloat32Array()

@export_group("Cadencia")
## Ventana entre un tiro y el siguiente, en la primera oleada.
@export var min_interval: float = 18.0
@export var max_interval: float = 34.0
## Cuanto se acorta la ventana por oleada. Las oleadas altas son las que piden
## mas gadget, asi que el publico se entusiasma con ellas.
@export var interval_step_per_wave: float = 1.4
## Piso de la ventana. Sin esto, en la oleada 20 el publico tira sin parar y el
## gadget deja de ser un recurso que hay que administrar.
@export var min_interval_floor: float = 8.0
## Espera antes del primer tiro de cada oleada. El publico mira un rato antes de
## meterse: sin esto cada oleada empieza con un regalo y el arranque se aplana.
@export var opening_delay: float = 12.0


## Segundos hasta el proximo tiro en la oleada `wave_index` (0-based).
func roll_interval(wave_index: int, rng: RandomNumberGenerator) -> float:
	var shift: float = interval_step_per_wave * float(maxi(wave_index, 0))
	var low: float = maxf(min_interval - shift, min_interval_floor)
	var high: float = maxf(max_interval - shift, low)
	return rng.randf_range(low, high)


## Una utilidad al azar entre las que `allowed` deja pasar, respetando los pesos.
##
## `allowed` es como se filtra lo que el jugador ya tiene lleno: tirarle una
## granada a alguien con tres granadas es tirar basura a la arena, y el publico
## no puede quedar como que no mira lo que pasa abajo.
func pick(rng: RandomNumberGenerator, allowed: Callable = Callable()) -> UtilityData:
	var pool: Array[UtilityData] = []
	var pool_weights: PackedFloat32Array = PackedFloat32Array()
	var total: float = 0.0
	for i: int in utilities.size():
		var data: UtilityData = utilities[i]
		if data == null:
			continue
		if allowed.is_valid() and not bool(allowed.call(data)):
			continue
		var weight: float = maxf(weights[i] if i < weights.size() else 1.0, 0.0)
		if is_zero_approx(weight):
			continue
		pool.push_back(data)
		pool_weights.push_back(weight)
		total += weight
	if pool.is_empty():
		return null

	var roll: float = rng.randf() * total
	for i: int in pool.size():
		roll -= pool_weights[i]
		if roll <= 0.0:
			return pool[i]
	return pool[pool.size() - 1]
