@tool
class_name MusicPlaylist
extends Resource
## Which tracks play in which phase of the game, and how loud the bed sits.
##
## Two lists, not four: the shop is not a mood of its own. Walking out of a wave
## into the armoury and back is one continuous stretch of a run, and cutting the
## music at that door makes the shop feel like a different game. So the run list
## covers fighting and shopping alike, and the manager simply keeps playing.
##
## A resource rather than a table in code because "which song goes where" is a
## taste call somebody should be able to change without opening a script.

@export_group("Tracks")
## The menu, and whatever comes after a run ends.
@export var menu_tracks: Array[AudioStream] = []
## A whole run: waves and the shop between them.
@export var run_tracks: Array[AudioStream] = []
## Optional. Empty falls back to `menu_tracks`, which is the honest default -
## a run ending is not a mood of its own either, it is a return to the menu.
@export var game_over_tracks: Array[AudioStream] = []

@export_group("Level")
## Where the bed sits under everything else, before the player's music slider.
##
## Deliberately far down. These are full songs, mastered loud, next to game SFX
## that peak at -1 dBFS and are meant to carry information - a windup, a
## reload, a door opening. Music that competes with those is music that hides
## them, so it plays quiet enough to be a floor rather than a layer.
@export_range(-40.0, 0.0, 0.5) var bed_volume_db: float = -14.0
## Seconds to fade between tracks, and to fade the first one in.
@export_range(0.0, 8.0, 0.1) var crossfade_time: float = 1.5


## The list a game state should be playing from, or empty when the state has no
## music of its own.
func tracks_for_phase(phase: StringName) -> Array[AudioStream]:
	match phase:
		&"menu":
			return menu_tracks
		&"run":
			return run_tracks
		&"game_over":
			return game_over_tracks if not game_over_tracks.is_empty() else menu_tracks
	return []


## True when every list is empty - the manager stays silent rather than warning
## once per state change.
func is_empty() -> bool:
	return menu_tracks.is_empty() and run_tracks.is_empty() and game_over_tracks.is_empty()
