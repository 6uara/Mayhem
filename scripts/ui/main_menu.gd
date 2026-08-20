extends Control
## The first screen of the game, and until now the only one that never got the
## visual pass - it was a placeholder so GameManager's scene transitions had
## somewhere to land, and it outlived that job by several phases.
##
## Both panels it opens are the same scenes the pause menu uses. A settings screen
## that behaves differently depending on where it was opened from is a bug waiting
## to be written, so there is only one of it.

@onready var _root: Control = $Root
@onready var _play_button: Button = $Root/Panel/Margin/Layout/PlayButton
@onready var _coop_button: Button = $Root/Panel/Margin/Layout/CoopButton
@onready var _leaderboard_button: Button = $Root/Panel/Margin/Layout/LeaderboardButton
@onready var _options_button: Button = $Root/Panel/Margin/Layout/OptionsButton
@onready var _quit_button: Button = $Root/Panel/Margin/Layout/QuitButton
@onready var _best: Label = $Root/Panel/Margin/Layout/BestRow/Value
@onready var _footer: Label = $Root/Panel/Margin/Layout/Footer
@onready var _settings: SettingsScreen = $Settings
@onready var _leaderboard: LeaderboardPanel = $Leaderboard
@onready var _coop: CoopPanel = $Coop


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_play_button.pressed.connect(_on_play_pressed)
	_coop_button.pressed.connect(_on_coop_pressed)
	_leaderboard_button.pressed.connect(_on_leaderboard_pressed)
	_options_button.pressed.connect(_on_options_pressed)
	_quit_button.pressed.connect(get_tree().quit)
	_settings.closed.connect(_on_panel_closed)
	_leaderboard.closed.connect(_on_panel_closed)
	_coop.closed.connect(_on_panel_closed)
	_refresh_best()
	_set_footer()
	_play_button.grab_focus()


# Private

## The one number worth putting on the front page: the thing the next run is for.
func _refresh_best() -> void:
	var best: int = SaveManager.get_best_score()
	_best.text = "%d" % best if best > 0 else "-"


## The ownership line the LICENSE and the itch.io page also carry. Cheap to show,
## and it is the one place a player who never reads a store page still sees it -
## which is exactly the audience that matters if a build ever turns up re-uploaded
## somewhere it should not be. Version comes from config/version so a build can
## always be identified from a screenshot in a bug report.
func _set_footer() -> void:
	var version: String = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	_footer.text = "v%s  -  (c) 2026 Juan Guaragnini.  All rights reserved." % version


func _on_play_pressed() -> void:
	GameManager.restart_run()


func _on_coop_pressed() -> void:
	_root.visible = false
	_coop.open()


func _on_leaderboard_pressed() -> void:
	_root.visible = false
	_leaderboard.open()


func _on_options_pressed() -> void:
	_root.visible = false
	_settings.open()


func _on_panel_closed() -> void:
	_root.visible = true
	_refresh_best()
	_play_button.grab_focus()
