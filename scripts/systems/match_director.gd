class_name MatchDirector
extends Node
## Runs the closed 10-wave session: starts waves, handles the gap between them,
## and resolves the match into victory or game over.
##
## The between-wave gap is a plain timer for now; Phase 4 replaces it with the
## shop phase, which is why the duration lives in one exported constant.

signal match_state_changed(is_running: bool)

## Waves in order. Authored as .tres so composition is data, not code.
@export var waves: Array[WaveData] = []
@export var spawner: EnemySpawner
@export var first_wave_delay: float = 3.0
## Fallback gap when there is no shop screen wired.
@export var between_wave_delay: float = 6.0
## The shop phase between waves (CLAUDE.md 5.5: ~20-30s, skippable).
@export var shop_screen: CanvasLayer
## Beat between the wave clearing and the shop opening, so the last kill lands.
@export var shop_open_delay: float = 1.5

var is_running: bool = false

var _match_start_time: float = 0.0
## Guards against a wave_completed arriving after the run already ended.
var _generation: int = 0


func _ready() -> void:
	EventBus.wave_completed.connect(_on_wave_completed)
	EventBus.player_died.connect(_on_player_died)
	EventBus.player_downed.connect(_on_player_downed)
	start_match.call_deferred()


# Public API

func start_match() -> void:
	if waves.is_empty():
		push_warning("MatchDirector: no waves authored, nothing to run")
		return
	_generation += 1
	is_running = true
	_match_start_time = _now()
	UpgradeManager.reset()
	EconomyManager.reset()
	WaveManager.reset()
	WaveManager.setup(waves)
	GameManager.start_run()
	match_state_changed.emit(true)
	# Every peer sets the match up - the wave list feeds the HUD, and the run
	# has to start locally for input and the reticle to come alive. Only the
	# host sequences the waves: a client running this too would spawn a second
	# horde that only it can see, on its own timer, while the host's enemies
	# arrive over the network alongside them.
	if not NetworkManager.is_host():
		return
	_start_wave_after(first_wave_delay, _generation)


func get_match_time() -> float:
	if not is_running:
		return 0.0
	return _now() - _match_start_time


# Private

func _start_wave_after(delay: float, generation: int) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if generation != _generation or not is_running:
		return
	if not WaveManager.start_next_wave():
		_finish_match()


func _on_wave_completed(wave_index: int, duration: float, _damage: float) -> void:
	if not is_running:
		return
	# Commentary is HostDirector's job - this one sequences waves.
	if WaveManager.is_last_wave():
		_finish_match()
		return
	_run_shop_phase(wave_index, duration, _generation)


## Opens the shop, waits for the player to leave it, then starts the next wave.
func _run_shop_phase(wave_index: int, duration: float, generation: int) -> void:
	if shop_screen == null or not shop_screen.has_method(&"open"):
		_start_wave_after(between_wave_delay, generation)
		return

	await get_tree().create_timer(shop_open_delay).timeout
	if generation != _generation or not is_running:
		return

	GameManager.state = GameManager.State.SHOPPING
	shop_screen.call(&"open", WaveManager.get_last_breakdown(), wave_index, duration)
	await shop_screen.shop_closed
	if generation != _generation or not is_running:
		return

	GameManager.state = GameManager.State.PLAYING
	_start_wave_after(0.5, generation)


## Victory: score is submitted to the local leaderboard and the run ends.
func _finish_match() -> void:
	if not is_running:
		return
	is_running = false
	_generation += 1
	var total_time: float = get_match_time()
	var score: int = _calculate_score(total_time)
	SaveManager.submit_score(score, total_time, waves.size())
	GameManager.state = GameManager.State.GAME_OVER
	EventBus.match_completed.emit(score, total_time)
	match_state_changed.emit(false)


## In coop, one death does not end the run. The others fight on and whoever fell
## watches from a teammate's camera; the match is over only once nobody is left
## standing. The host alone gets to call that, so every peer ends on the same
## wave with the same score rather than each deciding for itself.
func _on_player_downed(_peer_id: int) -> void:
	if not is_running or not NetworkManager.is_online() or not NetworkManager.is_host():
		return
	if not Players.alive().is_empty():
		return
	_declare_wipe.rpc()


@rpc("authority", "call_local", "reliable")
func _declare_wipe() -> void:
	EventBus.player_died.emit()


func _on_player_died() -> void:
	if not is_running:
		return
	is_running = false
	_generation += 1
	match_state_changed.emit(false)


## Rewards speed rather than pure completion (CLAUDE.md 5.5). Currency banked
## stands in for accuracy until Phase 4 tracks shots landed.
func _calculate_score(total_time: float) -> int:
	var time_bonus: int = int(maxf(0.0, 1200.0 - total_time) * 10.0)
	return EconomyManager.currency * 10 + time_bonus


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
