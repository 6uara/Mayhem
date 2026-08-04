extends CanvasLayer
## The pause menu.
##
## Pausing already worked - GameManager froze the tree and released the mouse - but
## nothing was drawn over it, so pressing escape mid-run read as the game hanging:
## a frozen frame, a loose cursor and no way out that the player could see.
##
## This draws that state and gives it exits. It also carries the only route to the
## options screen, which is why the whole of SettingsManager was unreachable.

@onready var _root: Control = $Root
@onready var _resume_button: Button = $Root/Panel/Margin/Layout/ResumeButton
@onready var _options_button: Button = $Root/Panel/Margin/Layout/OptionsButton
@onready var _menu_button: Button = $Root/Panel/Margin/Layout/MenuButton
@onready var _settings: SettingsScreen = $Settings


func _ready() -> void:
	# Everything here has to keep running while the tree is frozen.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.visible = false
	_resume_button.pressed.connect(_on_resume_pressed)
	_options_button.pressed.connect(_on_options_pressed)
	_menu_button.pressed.connect(_on_menu_pressed)
	_settings.closed.connect(_on_settings_closed)
	EventBus.game_paused.connect(_on_game_paused)


# Private

func _on_game_paused(paused: bool) -> void:
	_root.visible = paused
	if paused:
		_resume_button.grab_focus()
		return
	# Unpausing from anywhere - including escape while the options are open - has to
	# leave the whole stack closed, or the next pause reopens onto a stale screen.
	if _settings.visible:
		_settings.close()


func _on_resume_pressed() -> void:
	GameManager.set_paused(false)


func _on_options_pressed() -> void:
	_root.visible = false
	_settings.open()


func _on_settings_closed() -> void:
	# Only come back to the pause panel if the match is in fact still paused.
	_root.visible = GameManager.is_paused


func _on_menu_pressed() -> void:
	GameManager.set_paused(false)
	GameManager.return_to_menu()
