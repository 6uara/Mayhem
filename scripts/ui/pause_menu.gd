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
@onready var _skip_tutorial_button: Button = $Root/Panel/Margin/Layout/SkipTutorialButton
@onready var _feedback_button: Button = $Root/Panel/Margin/Layout/FeedbackButton
@onready var _editor_button: Button = $Root/Panel/Margin/Layout/EditorButton
@onready var _menu_button: Button = $Root/Panel/Margin/Layout/MenuButton
@onready var _settings: SettingsScreen = $Settings
@onready var _feedback: FeedbackPanel = $Feedback


func _ready() -> void:
	# Everything here has to keep running while the tree is frozen.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.visible = false
	_resume_button.pressed.connect(_on_resume_pressed)
	_options_button.pressed.connect(_on_options_pressed)
	_skip_tutorial_button.pressed.connect(_on_skip_tutorial_pressed)
	_skip_tutorial_button.visible = false
	_feedback_button.pressed.connect(_on_feedback_pressed)
	_editor_button.pressed.connect(_on_editor_pressed)
	_menu_button.pressed.connect(_on_menu_pressed)
	_settings.closed.connect(_on_settings_closed)
	_feedback.closed.connect(_on_settings_closed)
	EventBus.game_paused.connect(_on_game_paused)


# Private

func _on_game_paused(paused: bool) -> void:
	_root.visible = paused
	# Only a playtest launched from the arena editor has an editor to go back to.
	_editor_button.visible = ArenaSession.is_playtesting
	# Solo mientras corre el tutorial de arranque.
	_skip_tutorial_button.visible = TutorialHintManager.is_tutorial_running()
	if paused:
		_resume_button.grab_focus()
		# Llega con inercia en vez de aparecer: la pausa es un estado al que se
		# entra, no un cuadro que se pega encima del juego.
		UiMotion.enter(_root.get_node(^"Panel") as Control)
		return
	# Unpausing from anywhere - including escape while the options are open - has to
	# leave the whole stack closed, or the next pause reopens onto a stale screen.
	if _settings.visible:
		_settings.close()
	if _feedback.visible:
		_feedback.close()


func _on_resume_pressed() -> void:
	GameManager.set_paused(false)


## Saltea el tutorial y vuelve al juego: la primera oleada arranca enseguida.
func _on_skip_tutorial_pressed() -> void:
	TutorialHintManager.skip_tutorial()
	GameManager.set_paused(false)


func _on_options_pressed() -> void:
	_root.visible = false
	_settings.open()


## El momento en que algo molesta es durante la run, no despues: un reporte que
## hay que acordarse de escribir al volver al menu no se escribe nunca.
func _on_feedback_pressed() -> void:
	_root.visible = false
	_feedback.open()


func _on_settings_closed() -> void:
	# Only come back to the pause panel if the match is in fact still paused.
	_root.visible = GameManager.is_paused


func _on_editor_pressed() -> void:
	GameManager.set_paused(false)
	ArenaSession.return_to_editor()


func _on_menu_pressed() -> void:
	GameManager.set_paused(false)
	GameManager.return_to_menu()
