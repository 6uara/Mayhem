extends Node
## Crossfades a looping music bed to match GameManager's own state machine.
## Owns two AudioStreamPlayers on BUS_MUSIC directly rather than going through
## AudioPool's one-shot pool - a loop needs a stable, addressable player to fade,
## which "grab whichever pooled player is free" cannot promise.
##
## Ducking under Host VO reuses AudioPool.push_duck()/pop_duck() (see
## AudioPool._apply_duck) rather than a second mechanism - NarratorManager
## already calls push_duck()/pop_duck() around every line, so Music ducks for
## free the moment AudioPool started including BUS_MUSIC in that ref-counted duck.

const CROSSFADE_TIME: float = 1.5

const TRACK_PATHS: Dictionary = {
	GameManager.State.MENU: "res://assets/audio/music/menu.wav",
	GameManager.State.PLAYING: "res://assets/audio/music/combat.wav",
	GameManager.State.SHOPPING: "res://assets/audio/music/shop.wav",
	# No dedicated game-over cue in this pass - the menu bed covers it (a run
	# ending is not a distinct mood the way shopping vs. fighting is).
	GameManager.State.GAME_OVER: "res://assets/audio/music/menu.wav",
}

var _players: Array[AudioStreamPlayer] = []
var _active: AudioStreamPlayer
var _current_path: String = ""
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i: int in 2:
		var player := AudioStreamPlayer.new()
		player.name = "Track%d" % i
		player.bus = AudioPool.BUS_MUSIC
		player.volume_db = -80.0
		add_child(player)
		_players.push_back(player)
	EventBus.game_state_changed.connect(_on_game_state_changed)
	_on_game_state_changed(int(GameManager.state))


# Private

func _on_game_state_changed(new_state: int) -> void:
	var path: String = String(TRACK_PATHS.get(new_state, ""))
	if path == "" or path == _current_path:
		return
	_current_path = path
	_crossfade_to(path)


func _crossfade_to(path: String) -> void:
	if not ResourceLoader.exists(path):
		push_warning("MusicManager: no track at %s" % path)
		return
	var stream: AudioStreamWAV = load(path)
	# Loop set here rather than trusted to the .wav's own import settings - the
	# placeholder tracks (tools/generate_placeholder_music.py) are raw wave
	# output with no guarantee an .import file has loop_mode configured yet.
	if stream != null:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD

	var incoming: AudioStreamPlayer = _next_player()
	incoming.stream = stream
	incoming.volume_db = -80.0
	incoming.play()

	var outgoing: AudioStreamPlayer = _active
	_active = incoming

	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(incoming, "volume_db", 0.0, CROSSFADE_TIME)
	if outgoing != null:
		_tween.tween_property(outgoing, "volume_db", -80.0, CROSSFADE_TIME)
		_tween.chain().tween_callback(outgoing.stop)


func _next_player() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _players:
		if player != _active:
			return player
	return _players[0]
