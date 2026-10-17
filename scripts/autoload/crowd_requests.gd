extends Node
## Los pedidos del publico: cada tanto, durante una oleada, la tribuna pide algo
## -"¡queremos un 360!", "¡tres en el aire!"- y si el jugador lo cumple a tiempo,
## el publico paga en rating, en plata y con un regalo.
##
## Un pedido por vez, y con aire entre uno y otro: un pedido encima de otro es una
## lista de tareas, no un show. Se cuenta por `kill_payout`, que es donde ya
## viene juzgado el estilo de cada kill (KillBonusTracker): esto no mide nada
## propio.
##
## Autoload, como BroadcastRules, y por la misma razon: lo enciende
## `MatchDirector` (con las reglas de transmision, que son la otra mitad del
## show), asi que una prueba que emite `wave_started` no se encuentra con un
## pedido que nadie pidio.

const POOL_PATH: String = "res://data/crowd_requests/request_pool.tres"

## Solo pide cosas cuando esto es true.
var enabled: bool = false
var pool: CrowdRequestPool
## El pedido en curso, o null.
var active: CrowdRequest
var progress: int = 0
var time_left: float = 0.0

var _running: bool = false
var _wait: float = 0.0
var _last_id: StringName = &""
var _rng: RandomNumberGenerator:
	get:
		return RunSeed.rng(&"crowd_requests")


func _ready() -> void:
	pool = load(POOL_PATH) as CrowdRequestPool
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.wave_completed.connect(_on_wave_over.unbind(3))
	EventBus.player_died.connect(_on_wave_over)
	EventBus.kill_payout.connect(_on_kill_payout)


func _process(delta: float) -> void:
	if not _running:
		return
	if active != null:
		time_left -= delta
		if time_left <= 0.0:
			_finish(false)
		return
	_wait -= delta
	if _wait <= 0.0:
		start_request(pick())


# Public API

func reset() -> void:
	_running = false
	_last_id = &""
	if active != null:
		_finish(false)


## Un pedido al azar del pozo, sin repetir el ultimo.
func pick() -> CrowdRequest:
	if pool == null or pool.requests.is_empty():
		return null
	var candidates: Array[CrowdRequest] = []
	for request: CrowdRequest in pool.requests:
		if request != null and request.id != _last_id:
			candidates.append(request)
	if candidates.is_empty():
		candidates.append(pool.requests[0])
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


## Arranca `request` ahora. Publica para la consola y las pruebas.
func start_request(request: CrowdRequest) -> void:
	if request == null:
		_wait = _roll_interval()
		return
	active = request
	progress = 0
	time_left = request.time_limit
	_last_id = request.id
	EventBus.crowd_request_started.emit(request.id, request.title, request.goal,
		request.time_limit)


func find(request_id: StringName) -> CrowdRequest:
	if pool == null:
		return null
	for request: CrowdRequest in pool.requests:
		if request != null and request.id == request_id:
			return request
	return null


# Private

func _on_wave_started(wave_index: int, _wave: WaveData) -> void:
	if active != null:
		_finish(false)
	_running = enabled and pool != null and wave_index + 1 >= pool.from_wave
	_wait = pool.first_delay if pool != null else 0.0


## La oleada termino con un pedido abierto: se cierra sin premio. No es que el
## jugador fallo, es que no hubo tiempo; pero un pedido no sobrevive a su oleada.
func _on_wave_over() -> void:
	_running = false
	if active != null:
		_finish(false)


func _on_kill_payout(_reward: int, bonus_ids: Array, _bonus_total: int,
		_position: Vector3) -> void:
	if active == null or not bonus_ids.has(active.bonus_id):
		return
	progress += 1
	EventBus.crowd_request_progress.emit(active.id, progress, active.goal)
	if progress >= active.goal:
		_finish(true)


func _finish(success: bool) -> void:
	var request: CrowdRequest = active
	active = null
	time_left = 0.0
	_wait = _roll_interval()
	if success:
		BroadcastRating.boost(request.reward_rating)
		EconomyManager.award_show_bonus(request.reward_currency)
	# El regalo lo tira CrowdDropDirector, que es quien sabe tirar: escucha esto.
	EventBus.crowd_request_ended.emit(request.id, success)


func _roll_interval() -> float:
	if pool == null:
		return 30.0
	return _rng.randf_range(pool.min_interval, maxf(pool.max_interval, pool.min_interval))
