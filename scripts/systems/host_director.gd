class_name HostDirector
extends Node
## Decides when the Host speaks. Owns no lines and no pacing - it watches the match
## and names the occasion, NarratorManager does the rest.
##
## This exists so gameplay systems do not carry commentary. Before it, the only two
## lines in the game were string literals inside MatchDirector, which is a system
## about wave sequencing: adding a third would have meant editing match flow to
## write a joke.
##
## In coop the Host is one broadcast rather than four commentators, so the match
## beats are decided on the host and spoken everywhere (say_shared). Two are
## deliberately left personal and local: the low-health warning, which is about
## your hit points and would otherwise tell four people that one of them is in
## trouble, and the purchase quip, which would turn a shop phase where everyone
## is buying at once into four voices talking over each other.
##
## The kill-based lines read the whole team's kills, not yours: the host's
## enemy_killed fires for every death in the arena, including the ones a client
## shot, so first blood is the session's first blood and a streak is the team on
## a run.

## Kills inside this window that count as a run worth remarking on.
@export var streak_kills: int = 4
@export var streak_window: float = 6.0

var _kill_times: Array[float] = []
var _first_blood_done: bool = false
var _low_health_announced: bool = false


func _ready() -> void:
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.wave_completed.connect(_on_wave_completed)
	EventBus.enemy_killed.connect(_on_enemy_killed.unbind(3))
	EventBus.player_damaged.connect(_on_player_damaged.unbind(1))
	EventBus.player_died.connect(_on_player_died)
	EventBus.match_completed.connect(_on_match_completed.unbind(2))
	EventBus.purchase_made.connect(_on_purchase_made.unbind(2))


# Private

func _on_wave_started(wave_index: int, config: WaveData) -> void:
	# Every peer resets its own bookkeeping - a client that never speaks still
	# has to forget last wave's low-health warning.
	_kill_times.clear()
	_first_blood_done = false
	_low_health_announced = false
	if not NetworkManager.is_host():
		return
	# The elite billing replaces the ordinary one rather than stacking with it -
	# two lines back to back is exactly the noise the pacing rules exist to stop.
	if config != null and config.is_elite_wave:
		NarratorManager.say_shared(&"elite_wave")
		return
	NarratorManager.say_shared(&"wave_start", [wave_index + 1])


func _on_wave_completed(wave_index: int, duration: float, damage_taken: float) -> void:
	if not NetworkManager.is_host():
		return
	var wave: WaveData = WaveManager.get_current_wave()
	# A clean wave is the rarer thing, so it gets the punchline slot; being slow is
	# only worth mentioning when the clock was actually missed.
	if is_zero_approx(damage_taken):
		NarratorManager.say_shared(&"no_damage")
		return
	if wave != null and duration > wave.par_time:
		NarratorManager.say_shared(&"too_slow")
		return
	NarratorManager.say_shared(&"wave_cleared", [wave_index + 1])


func _on_enemy_killed() -> void:
	if not NetworkManager.is_host():
		return
	if not _first_blood_done:
		_first_blood_done = true
		NarratorManager.say_shared(&"first_blood")
		return

	var now: float = float(Time.get_ticks_msec()) / 1000.0
	_kill_times.push_back(now)
	while not _kill_times.is_empty() and now - _kill_times[0] > streak_window:
		_kill_times.pop_front()
	if _kill_times.size() >= streak_kills:
		_kill_times.clear()
		NarratorManager.say_shared(&"streak")


## Once per wave: the Host notes that the player is in trouble, he does not narrate
## every hit that follows.
func _on_player_damaged(remaining: float) -> void:
	if _low_health_announced:
		return
	var player: Node = Players.local()
	if player == null:
		return
	var health: HealthComponent = (player as Player).health if player is Player else null
	if health == null or health.max_health <= 0.0:
		return
	if remaining / health.max_health > Tokens.LOW_HEALTH_PCT:
		return
	_low_health_announced = true
	NarratorManager.say(&"low_health")


## The run is over for everybody at once, so it gets one obituary.
func _on_player_died() -> void:
	if not NetworkManager.is_host():
		return
	NarratorManager.say_shared(&"death")


func _on_match_completed() -> void:
	if not NetworkManager.is_host():
		return
	NarratorManager.say_shared(&"match_won")


func _on_purchase_made() -> void:
	NarratorManager.say(&"purchase")
