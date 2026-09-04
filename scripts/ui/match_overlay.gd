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
@onready var _score_entry: ScoreEntryPanel = $ScoreEntry

var _banner_timer: float = 0.0
## Lo que la pantalla de fin va a decir en cuanto el panel de nombre se cierre.
var _pending_title: String = ""
var _pending_details: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_end_panel.visible = false
	_banner.text = ""
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.wave_completed.connect(_on_wave_completed)
	# El final de la run entra por una sola señal, ganada o perdida. Escuchar
	# `match_completed` y `player_died` por separado dejaba el orden entre el
	# panel de nombre y la pantalla de fin a merced del orden de conexion.
	EventBus.run_finished.connect(_on_run_finished)
	_score_entry.saved.connect(_on_score_saved)
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


## Primero el nombre, despues la pantalla de fin: al reves, el "Best" que la
## pantalla muestra seria el de antes de anotar esta misma run.
func _on_run_finished(score: int, total_time: float, waves_cleared: int,
		victory: bool) -> void:
	_pending_title = "VICTORY" if victory else "GAME OVER"
	if victory:
		_pending_details = "Score %d\nTime %s\nWaves %d of %d" % [
			score, _format_time(total_time), waves_cleared, WaveManager.WAVE_COUNT]
	else:
		_pending_details = "Score %d\nWave %d of %d\nNo revives. No second chances." % [
			score, waves_cleared + 1, WaveManager.WAVE_COUNT]
	_banner.text = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_score_entry.open(score, total_time, waves_cleared)


func _on_score_saved() -> void:
	_show_end(_pending_title, "%s\nBest %d" % [
		_pending_details, SaveManager.get_best_score()])


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
