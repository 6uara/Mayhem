extends Node
## Plays the music bed, following GameManager's state machine.
##
## Owns two AudioStreamPlayers on BUS_MUSIC directly rather than going through
## AudioPool's one-shot pool - a bed needs a stable, addressable player to fade,
## which "grab whichever pooled player is free" cannot promise.
##
## Two rules shape everything here:
##
## 1. **The shop is not a different mood.** Walking out of a wave into the
##    armoury and back is one continuous stretch of a run, so PLAYING and
##    SHOPPING share a phase and the track simply keeps going. Cutting the music
##    at that door made the shop feel like a different game.
## 2. **The bed sits under the game.** Tracks are full songs mastered loud, next
##    to SFX that peak at -1 dBFS and carry information - a windup, a reload, a
##    door. `MusicPlaylist.bed_volume_db` is what keeps the music a floor rather
##    than a competing layer; the player's music slider scales the bus on top.
##
## Ducking under Host VO reuses AudioPool.push_duck()/pop_duck() (see
## AudioPool._apply_duck) rather than a second mechanism.

const PLAYLIST_PATH: String = "res://data/audio/music_playlist.tres"

## Which phase each game state belongs to. Two states share `run` on purpose;
## see the note above.
const PHASE_BY_STATE: Dictionary = {
	GameManager.State.MENU: &"menu",
	GameManager.State.PLAYING: &"run",
	GameManager.State.SHOPPING: &"run",
	GameManager.State.GAME_OVER: &"game_over",
}

## Silence, for the far end of every fade.
const SILENT_DB: float = -80.0

var playlist: MusicPlaylist

var _players: Array[AudioStreamPlayer] = []
var _active: AudioStreamPlayer
var _phase: StringName = &""
var _current_stream: AudioStream
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	playlist = load(PLAYLIST_PATH) as MusicPlaylist
	if playlist == null:
		push_warning("MusicManager: no playlist at %s" % PLAYLIST_PATH)
		playlist = MusicPlaylist.new()
	for i: int in 2:
		var player := AudioStreamPlayer.new()
		player.name = "Track%d" % i
		player.bus = AudioPool.BUS_MUSIC
		player.volume_db = SILENT_DB
		# Tracks are songs, not loops: when one ends the bed moves to the next.
		player.finished.connect(_on_track_finished.bind(player))
		add_child(player)
		_players.push_back(player)
	EventBus.game_state_changed.connect(_on_game_state_changed)
	_on_game_state_changed(int(GameManager.state))


# Public API

## The phase whose list is playing, for tests and for anything that wants to
## know whether the shop kept the run's track.
func get_phase() -> StringName:
	return _phase


func is_playing() -> bool:
	return _active != null and _active.playing


# Private

func _on_game_state_changed(new_state: int) -> void:
	var phase: StringName = PHASE_BY_STATE.get(new_state, &"")
	if phase == &"":
		return
	var tracks: Array[AudioStream] = playlist.tracks_for_phase(phase)
	if tracks.is_empty():
		return
	# Same phase, still playing: leave it alone. This is what makes the shop
	# door silent - SHOPPING and PLAYING are both `run`.
	if phase == _phase and is_playing():
		return
	_phase = phase
	_play(_pick(tracks))


## Picks a track from `tracks`, avoiding the one that just played when there is
## more than one to choose from.
func _pick(tracks: Array[AudioStream]) -> AudioStream:
	if tracks.size() == 1:
		return tracks[0]
	var options: Array[AudioStream] = tracks.duplicate()
	options.erase(_current_stream)
	if options.is_empty():
		options = tracks.duplicate()
	return options[randi() % options.size()]


func _play(stream: AudioStream) -> void:
	if stream == null:
		return
	_current_stream = stream

	var incoming: AudioStreamPlayer = _next_player()
	incoming.stream = stream
	incoming.volume_db = SILENT_DB
	incoming.play()

	var outgoing: AudioStreamPlayer = _active
	_active = incoming

	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(incoming, "volume_db", playlist.bed_volume_db,
		playlist.crossfade_time)
	if outgoing != null:
		_tween.tween_property(outgoing, "volume_db", SILENT_DB, playlist.crossfade_time)
		_tween.chain().tween_callback(outgoing.stop)


## A track running out is not the end of the music: the phase keeps playing with
## whatever comes next. Only the player that is actually the bed counts - the
## one fading out finishes too, and it has nothing to say.
func _on_track_finished(player: AudioStreamPlayer) -> void:
	if player != _active or _phase == &"":
		return
	var tracks: Array[AudioStream] = playlist.tracks_for_phase(_phase)
	if tracks.is_empty():
		return
	_play(_pick(tracks))


func _next_player() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _players:
		if player != _active:
			return player
	return _players[0]
