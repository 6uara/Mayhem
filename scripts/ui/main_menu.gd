extends Control
## Placeholder menu so GameManager's scene transitions have somewhere to land.
## The real menu is built in Phase 5.

@onready var _play_button: Button = $VBox/PlayButton
@onready var _quit_button: Button = $VBox/QuitButton


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_play_button.pressed.connect(_on_play_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_play_button.grab_focus()


func _on_play_pressed() -> void:
	GameManager.restart_run()


func _on_quit_pressed() -> void:
	get_tree().quit()
