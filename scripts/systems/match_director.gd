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

## Extra seconds the host waits for a peer that has stopped answering before it
## starts the next wave without them. The shop closes itself after `duration`
## everywhere, so this only ever fires for a peer that is hung or half-gone -
## but without it one such peer freezes the run for everyone.
const READY_GRACE: float = 15.0

var is_running: bool = false

var _match_start_time: float = 0.0
## Guards against a wave_completed arriving after the run already ended.
var _generation: int = 0
## Host-side, during a wave break: peers that have finished shopping.
var _ready_peers: Dictionary = {}
## Bumped every time a break opens, so a late ready-up from the previous one
## cannot start a wave that is already running.
var _break_generation: int = 0
## True between the shop opening here and the host calling everyone back.
var _in_break: bool = false


func _ready() -> void:
	EventBus.wave_completed.connect(_on_wave_completed)
	EventBus.player_died.connect(_on_player_died)
	EventBus.player_downed.connect(_on_player_downed)
	# A peer leaving during the break is one fewer to wait for - and if it was
	# the last one anybody was waiting on, the wave has to start.
	NetworkManager.roster_changed.connect(_on_roster_changed)
	if shop_screen != null and shop_screen.has_signal(&"shop_closed"):
		shop_screen.connect(&"shop_closed", _on_local_shop_closed)
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


## Host: waits for the last kill to land, then puts everyone in the shop at once.
##
## The break is one moment for the whole session rather than a screen each peer
## opens when its own copy of the wave looks clear. Only the host knows when
## that is, and a client shopping while the host's next wave was already walking
## in is the shape of bug that ends a coop run in confusion.
func _run_shop_phase(wave_index: int, duration: float, generation: int) -> void:
	if shop_screen == null or not shop_screen.has_method(&"open"):
		_start_wave_after(between_wave_delay, generation)
		return

	await get_tree().create_timer(shop_open_delay).timeout
	if generation != _generation or not is_running:
		return

	if NetworkManager.is_online():
		_open_break.rpc(wave_index, duration)
	else:
		_open_break(wave_index, duration)


## Every peer, host included: the wave break starts here.
##
## call_local so the host takes exactly the path a client takes - it shops
## against the same clock, reports itself ready through the same door, and does
## not get a private shortcut into the next wave.
@rpc("authority", "call_local", "reliable")
func _open_break(wave_index: int, duration: float) -> void:
	if not is_running:
		return
	_in_break = true
	_break_generation += 1
	_ready_peers.clear()

	# The host banked its bonuses when it detected the clear; a client has been
	# told the wave is over and works out its own payout now. The numbers are
	# per-player - your kills, the damage *you* took - so they are computed on
	# the machine that has them rather than sent from the host.
	if not NetworkManager.is_host():
		WaveManager.award_local_wave_bonuses(duration)

	# Falling costs you the rest of the wave, not the rest of the run. The host
	# owns who is alive, so it stands everyone back up and the news travels with
	# each body's own revive message.
	if NetworkManager.is_host():
		_revive_the_fallen()
		_start_ready_deadline(_break_generation)

	GameManager.state = GameManager.State.SHOPPING
	shop_screen.call(&"open", WaveManager.get_last_breakdown(), wave_index, duration,
		NetworkManager.is_online())
	_announce_ready_count()


## Local player is done shopping. In solo that is the whole decision; in coop it
## is a vote, and the arena reopens when the last one is in.
func _on_local_shop_closed() -> void:
	if not is_running or not _in_break:
		return
	if not NetworkManager.is_online():
		_resume_from_break()
		return
	if NetworkManager.is_host():
		_mark_ready(NetworkManager.SERVER_ID)
		return
	_report_ready.rpc_id(NetworkManager.SERVER_ID)


@rpc("any_peer", "call_remote", "reliable")
func _report_ready() -> void:
	if not multiplayer.is_server():
		return
	_mark_ready(multiplayer.get_remote_sender_id())


func _mark_ready(peer_id: int) -> void:
	if not _in_break or not NetworkManager.is_host():
		return
	_ready_peers[peer_id] = true
	_broadcast_ready_count()
	_resume_if_everyone_is_in()


func _resume_if_everyone_is_in() -> void:
	if not NetworkManager.is_online():
		return
	if _count_ready() < NetworkManager.get_peer_ids().size():
		return
	_resume_break.rpc()


## Counted against the roster rather than off the size of the table: a peer that
## readied up and then dropped is still in there, and taking its word for it
## would leave the session one vote short of ever starting the next wave.
func _count_ready() -> int:
	var ready_count: int = 0
	for peer_id: int in NetworkManager.get_peer_ids():
		if _ready_peers.has(peer_id):
			ready_count += 1
	return ready_count


## Host only, and only after the shop has closed itself everywhere: a peer that
## stopped answering must not hold the other three in a menu forever.
func _start_ready_deadline(generation: int) -> void:
	var wait: float = _shop_duration() + READY_GRACE
	await get_tree().create_timer(wait).timeout
	if generation != _break_generation or not _in_break or not is_running:
		return
	if not NetworkManager.is_online():
		return
	push_warning("MatchDirector: starting the wave without every peer ready")
	_resume_break.rpc()


@rpc("authority", "call_local", "reliable")
func _resume_break() -> void:
	_resume_from_break()


func _resume_from_break() -> void:
	if not _in_break:
		return
	_in_break = false
	_break_generation += 1
	if shop_screen != null and shop_screen.has_method(&"force_close"):
		shop_screen.call(&"force_close")
	if not is_running:
		return
	GameManager.state = GameManager.State.PLAYING
	# Only the host sequences waves - see start_match(). Clients get the next
	# one the way they got this one, in the snapshot.
	if NetworkManager.is_host():
		_start_wave_after(0.5, _generation)


func _revive_the_fallen() -> void:
	for body: Node3D in Players.all():
		var player := body as Player
		if player != null and player.is_downed:
			player.revive_from_host()


func _on_roster_changed() -> void:
	if _in_break and NetworkManager.is_host():
		_broadcast_ready_count()
		_resume_if_everyone_is_in()


func _broadcast_ready_count() -> void:
	if not NetworkManager.is_online():
		return
	_receive_ready_count.rpc(_count_ready(), NetworkManager.get_peer_ids().size())


@rpc("authority", "call_local", "reliable")
func _receive_ready_count(ready_count: int, total: int) -> void:
	EventBus.shop_ready_changed.emit(ready_count, total)


## What a peer shows before the host has said anything: nobody is in yet, and
## the roster it already has is how many it is waiting for.
func _announce_ready_count() -> void:
	if not NetworkManager.is_online():
		return
	EventBus.shop_ready_changed.emit(_count_ready(),
		NetworkManager.get_peer_ids().size())


func _shop_duration() -> float:
	if shop_screen != null and &"duration" in shop_screen:
		return float(shop_screen.get(&"duration"))
	return between_wave_delay


## Victory. Called by the host, which is the only peer that knows the last wave
## is clear, and broadcast so nobody is left standing in an empty arena waiting
## for a wave that will never come.
func _finish_match() -> void:
	if not is_running:
		return
	if NetworkManager.is_online() and NetworkManager.is_host():
		_declare_victory.rpc()
		return
	_end_in_victory()


@rpc("authority", "call_local", "reliable")
func _declare_victory() -> void:
	_end_in_victory()


## The clock is the run's; the score is yours. Each peer scores its own wallet
## and writes its own leaderboard entry, so four people finishing the same run
## get four honest times rather than one shared number.
func _end_in_victory() -> void:
	if not is_running:
		return
	var total_time: float = get_match_time()
	is_running = false
	_generation += 1
	# is_running is already false, so this only takes the shop off the screen -
	# it cannot start an eleventh wave on the way out.
	_resume_from_break()
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
