class_name HostPresenter
extends Resource
## A selectable voice for the Host. Adding a presenter is a content job, not a
## code change: author a HostPresenter, drop the recordings under
## res://assets/audio/voice/<id>/<line_id>.ogg (see NarratorManager), done.

@export var id: StringName = &""
@export var display_name: String = ""
@export var icon: Texture2D
## Line played by the Settings screen's "Listen" button. Empty = no preview
## (the "Subtitles Only" presenter has nothing to play).
@export var preview_line_id: StringName = &""
