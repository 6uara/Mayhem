extends CanvasLayer
## Wave banners plus the victory and game-over screens.
## Restart has to be near-instant - under 2 seconds to be shooting again
## (CLAUDE.md 5.5), so this reloads the scene rather than unwinding state.

const BANNER_TIME: float = 2.0
const SHOP_CATALOG_PATH: String = "res://data/economy/shop_catalog.tres"

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
## La linea para compartir la run: arena, modo, hasta donde llego, puntaje y el
## codigo que la vuelve a jugar. Ver RunSeed.
var _share_text: String = ""
var _copy_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_end_panel.visible = false
	_banner.text = ""
	# El arranque de oleada no pasa por aca: lo anuncia la HUD (HUD.announce),
	# con el tratamiento elite incluido. Los dos a la vez eran el mismo "WAVE N"
	# dos veces en pantalla.
	EventBus.wave_completed.connect(_on_wave_completed)
	# El final de la run entra por una sola señal, ganada o perdida. Escuchar
	# `match_completed` y `player_died` por separado dejaba el orden entre el
	# panel de nombre y la pantalla de fin a merced del orden de conexion.
	EventBus.run_finished.connect(_on_run_finished)
	_score_entry.saved.connect(_on_score_saved)
	_restart_button.pressed.connect(_on_restart_pressed)
	_menu_button.pressed.connect(_on_menu_pressed)
	# Armado por codigo para no tocar la escena por un boton.
	_copy_button = Button.new()
	_copy_button.name = "CopyCodeButton"
	_copy_button.text = "Copy run code"
	_copy_button.tooltip_text = "Copies a line with your score and the code that replays this run."
	_copy_button.pressed.connect(_on_copy_pressed)
	_restart_button.get_parent().add_child(_copy_button)
	_restart_button.get_parent().move_child(_copy_button, _restart_button.get_index())


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
	# La oleada limpia aterriza como el cartel de oleada nueva: desde mas grande.
	_banner.pivot_offset = _banner.size * 0.5
	_banner.scale = Vector2.ONE * Tokens.ANNOUNCE_POP_SCALE
	var tween: Tween = _banner.create_tween()
	tween.tween_property(_banner, ^"scale", Vector2.ONE, Tokens.UI_ENTER_TIME) 		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
	# De donde salio el numero. Sin esto el puntaje es una cifra que no enseña
	# nada: lo que el jugador tiene que saber es que el estilo y las oleadas
	# pesan, y que morir solo corta lo que iba a seguir sumando.
	_pending_details += "\nKills %d  -  Style %d  -  Waves %d" % [
		RunRecord.kill_points, RunRecord.style_points, RunRecord.wave_points]
	# Que mato y de donde vino el daño: lo que hay que mirar en la proxima run.
	if not victory:
		var recap: String = death_recap_line(RunRecord.get_death_recap())
		if recap != "":
			_pending_details += "\n" + recap
	for line: String in mastery_lines(Armory.get_last_report()):
		_pending_details += "\n" + line
	_share_text = share_line(score, waves_cleared, victory)
	_pending_details += "\nRun code  %s" % RunSeed.make_code(RunSeed.run_seed,
		GameManager.run_mode, GameManager.get_starting_weapon_id())
	_banner.text = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_score_entry.open(score, total_time, waves_cleared)


## "Killed by Bomber  -  62% of your damage came from Ranger". Vacio si no hay de
## que hablar. Publico y estatico para las pruebas.
static func death_recap_line(recap: Dictionary) -> String:
	var killer := StringName(recap.get("killed_by", &""))
	if killer == &"":
		return ""
	var line: String = "Killed by %s" % DamageCause.label(killer)
	var top := StringName(recap.get("top_cause", &""))
	var share: int = roundi(float(recap.get("top_share", 0.0)) * 100.0)
	if top != &"" and top != killer:
		line += "  -  %d%% of your damage came from %s" % [share, DamageCause.label(top)]
	elif top == killer and share > 0:
		line += "  -  %d%% of all the damage you took" % share
	return line


## Una linea por arma que gano maestria en la run, con lo que desbloqueo.
static func mastery_lines(report: Array[Dictionary]) -> Array[String]:
	var lines: Array[String] = []
	var catalog := load(SHOP_CATALOG_PATH) as ShopCatalog
	for entry: Dictionary in report:
		var weapon_id := StringName(entry.get("weapon_id", &""))
		var weapon: WeaponData = catalog.find_weapon(weapon_id) if catalog != null else null
		var weapon_name: String = weapon.display_name if weapon != null else String(weapon_id)
		var line: String = "%s mastery  +%d XP  -  level %d" % [weapon_name,
			int(entry.get("gained", 0)), int(entry.get("level", 0))]
		var names: Array[String] = []
		for attachment: AttachmentData in entry.get("unlocked", []):
			names.append(attachment.display_name)
		if not names.is_empty():
			line += "  -  UNLOCKED %s" % ", ".join(names)
		lines.append(line)
	return lines


## La linea que se copia: lo que se ve en un mensaje, y el codigo para jugarla.
static func share_line(score: int, waves_cleared: int, victory: bool) -> String:
	var mode: String = GameManager.mode_label(GameManager.run_mode)
	var weapon: StringName = GameManager.get_starting_weapon_id()
	if weapon != &"":
		mode += " (%s)" % String(weapon).capitalize()
	var reached: String = "all %d waves" % WaveManager.WAVE_COUNT if victory \
		else "wave %d/%d" % [waves_cleared + 1, WaveManager.WAVE_COUNT]
	var arena: String = RunRecord.arena_name if RunRecord.arena_name != "" else "The Pit"
	return "MAYHEM  |  %s  |  %s  |  %s  |  %d pts  |  %s" % [arena, mode, reached, score,
		RunSeed.make_code(RunSeed.run_seed, GameManager.run_mode, weapon)]


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(_share_text)
	_copy_button.text = "Copied"


func _on_score_saved() -> void:
	_show_end(_pending_title, "%s\nBest %d" % [
		_pending_details, SaveManager.get_best_score(RunRecord.arena_id)])


func _show_end(title: String, details: String) -> void:
	_copy_button.text = "Copy run code"
	_end_title.text = title
	_end_details.text = details
	_end_panel.visible = true
	# El titulo cae y rebota; el resto sube detras. Es el final de la run: es el
	# unico cartel que puede pesar un poco mas.
	UiMotion.enter(_end_panel.get_node(^"VBox") as Control)
	UiMotion.punch(_end_title, Tokens.REWARD if title.contains("VICTORY") else Color.WHITE, 1.4)
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
