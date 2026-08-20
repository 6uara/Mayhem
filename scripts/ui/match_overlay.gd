extends CanvasLayer
## Wave banners plus the victory and game-over screens.
## Restart has to be near-instant - under 2 seconds to be shooting again
## (CLAUDE.md 5.5), so this reloads the scene rather than unwinding state.

const BANNER_TIME: float = 2.0

@onready var _banner: Label = $Banner
@onready var _end_panel: Control = $EndPanel
@onready var _end_title: Label = $EndPanel/VBox/Title
@onready var _end_details: Label = $EndPanel/VBox/Details
@onready var _restart_button: Button = $EndPanel/VBox/RestartButton
@onready var _menu_button: Button = $EndPanel/VBox/MenuButton

var _banner_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_end_panel.visible = false
	_banner.text = ""
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.wave_completed.connect(_on_wave_completed)
	EventBus.match_completed.connect(_on_match_completed)
	EventBus.player_died.connect(_on_player_died)
	# The one ending that is not about the match. Without it a client whose host
	# quit is left standing in an arena that has stopped: the enemies freeze
	# where their last snapshot put them, no wave ever ends, and nothing on
	# screen says why.
	NetworkManager.host_disconnected.connect(_on_host_disconnected)
	_restart_button.pressed.connect(_on_restart_pressed)
	_menu_button.pressed.connect(_on_menu_pressed)


func _process(delta: float) -> void:
	if _banner_timer > 0.0:
		_banner_timer -= delta
		_banner.modulate.a = clampf(_banner_timer / BANNER_TIME, 0.0, 1.0)
		if _banner_timer <= 0.0:
			_banner.text = ""


# Private

func _show_banner(text: String) -> void:
	_banner.text = text
	_banner_timer = BANNER_TIME
	_banner.modulate.a = 1.0


func _on_wave_started(wave_index: int, config: WaveData) -> void:
	var suffix: String = "  -  ELITE" if config != null and config.is_elite_wave else ""
	_show_banner("WAVE %d%s" % [wave_index + 1, suffix])


func _on_wave_completed(wave_index: int, duration: float, damage_taken: float) -> void:
	# The three income sources are shown explicitly in Phase 4's wave-complete
	# screen; this is the interim readout.
	var flawless: String = "  -  NO DAMAGE" if damage_taken <= 0.0 else ""
	_show_banner("WAVE %d CLEAR  -  %.1fs%s" % [wave_index + 1, duration, flawless])


func _on_match_completed(score: int, total_time: float) -> void:
	_show_end("VICTORY", "Score %d\nTime %s\nBest %d" % [
		score, _format_time(total_time), SaveManager.get_best_score()])


func _on_player_died() -> void:
	# Coop revives the fallen at every wave break, so the run only ends when the
	# whole team is down at once - which is a different sentence.
	var epitaph: String = "Nobody left standing." if NetworkManager.is_online() \
		else "No revives. No second chances."
	_show_end("GAME OVER", "Wave %d of %d\n%s" % [
		WaveManager.current_index + 1, WaveManager.WAVE_COUNT, epitaph])


## Restart is left enabled on purpose: the session is already torn down by the
## time this fires, so restarting starts an ordinary solo run rather than trying
## to rejoin something that is gone.
func _on_host_disconnected() -> void:
	_show_end("SESION TERMINADA", "El host cerro la partida.\nWave %d of %d" % [
		WaveManager.current_index + 1, WaveManager.WAVE_COUNT])


func _show_end(title: String, details: String) -> void:
	_end_title.text = title
	_end_details.text = details
	_end_panel.visible = true
	_banner.text = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_restart_button.grab_focus()


func _on_restart_pressed() -> void:
	ObjectPool.clear()
	GameManager.restart_run()


func _on_menu_pressed() -> void:
	ObjectPool.clear()
	GameManager.return_to_menu()


func _format_time(seconds: float) -> String:
	return "%d:%05.2f" % [int(seconds) / 60, fmod(seconds, 60.0)]
