extends Node
## Junta un reporte del jugador y lo deja en disco, mas el texto listo para
## pegar en cualquier lado.
##
## Nada sale de la maquina solo. Guardar escribe un archivo, "Copy" deja el
## reporte en el portapapeles y "Open form" abre el navegador: el jugador decide
## si lo manda y a donde, que es lo unico defendible para algo que incluye datos
## de su maquina - y lo unico que no obliga a declarar telemetria en Steam.
##
## Lo que hace util a un reporte es el contexto, y el contexto escrito a mano no
## llega nunca: nadie anota la version, la wave, la arena ni su GPU. Todo eso se
## adjunta solo.

const CONFIG_PATH: String = "res://data/feedback/feedback_config.tres"
## Una carpeta y no un archivo unico: los reportes se acumulan, y el segundo no
## puede pisar al primero.
const FEEDBACK_DIR: String = "user://feedback"

var config: FeedbackConfig

## Cuando arranco la sesion, para poder decir hace cuanto se esta jugando.
var _started_msec: int = 0
## Ultima arena cargada, si el jugador eligio una.
var _arena_name: String = ""


func _ready() -> void:
	_started_msec = Time.get_ticks_msec()
	config = load(CONFIG_PATH) as FeedbackConfig
	if config == null:
		push_warning("FeedbackManager: no config at %s, using defaults" % CONFIG_PATH)
		config = FeedbackConfig.new()


# Public API

func get_categories() -> Array[String]:
	return config.categories.duplicate()


func get_form_url() -> String:
	return config.form_url


func has_form() -> bool:
	return config.form_url.strip_edges() != ""


## Abre el formulario en el navegador. Devuelve false si no hay ninguno
## configurado, para que el boton pueda no existir en vez de no hacer nada.
func open_form() -> bool:
	if not has_form():
		return false
	OS.shell_open(config.form_url)
	return true


## El reporte entero como diccionario: lo que escribio el jugador mas el
## contexto que se arma solo.
func build_report(body: String, category: String) -> Dictionary:
	return {
		"category": category,
		"body": body.strip_edges(),
		"version": str(ProjectSettings.get_setting("application/config/version", "0.0.0")),
		"date": Time.get_datetime_string_from_system(false, true),
		"session_seconds": int(float(Time.get_ticks_msec() - _started_msec) / 1000.0),
		"arena": _arena_name,
		"wave": WaveManager.current_index + 1,
		"score": EconomyManager.currency,
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"gpu": RenderingServer.get_video_adapter_name(),
		"resolution": "%dx%d" % [
			DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"fps": Engine.get_frames_per_second(),
		# Con que capas del show se jugo (docs/PLAYTEST.md) y cual es el log de la
		# ultima run: el reporte dice "la ola 7 estaba imposible" y el log dice
		# por que.
		"layers_off": ", ".join(PlaytestLayers.get_disabled()),
		"last_run_log": latest_run_log().get_file(),
	}


## El mismo reporte en markdown, que es el formato que entra pegado en un issue,
## en un Discord o en un mail sin que nadie lo tenga que reformatear.
func format_report(report: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("**MAYHEM feedback - %s**" % report.get("category", "Other"))
	lines.append("")
	lines.append(String(report.get("body", "")))
	lines.append("")
	lines.append("---")
	for key: String in ["version", "date", "session_seconds", "arena", "wave",
			"score", "os", "gpu", "resolution", "fps", "layers_off", "last_run_log"]:
		lines.append("- %s: %s" % [key, report.get(key, "-")])
	return "\n".join(lines)


## Escribe el reporte y devuelve la ruta, o vacio si no se pudo. La ruta se le
## muestra al jugador: un archivo que no sabe donde quedo no lo manda nunca.
func save_report(report: Dictionary) -> String:
	if not DirAccess.dir_exists_absolute(FEEDBACK_DIR):
		var error: Error = DirAccess.make_dir_recursive_absolute(FEEDBACK_DIR)
		if error != OK:
			push_error("FeedbackManager: cannot create %s" % FEEDBACK_DIR)
			return ""
	var path: String = "%s/feedback_%d.json" % [FEEDBACK_DIR, Time.get_unix_time_from_system()]
	# El log de la ultima run va adentro del archivo, no al lado: el reporte que se
	# manda es uno solo, y un adjunto aparte es el que se olvida.
	var saved: Dictionary = report.duplicate()
	var log_path: String = latest_run_log()
	if log_path != "":
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(log_path))
		if parsed is Dictionary:
			saved["last_run"] = parsed
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("FeedbackManager: cannot write %s" % path)
		return ""
	file.store_string(JSON.stringify(saved, "\t"))
	return path


## La ruta del log de RunLogger mas nuevo, o vacio si no hay ninguno. El nombre
## lleva la fecha en ISO, asi que el ultimo en orden alfabetico es el ultimo.
func latest_run_log(log_dir: String = RunLogger.LOG_DIR) -> String:
	if not DirAccess.dir_exists_absolute(log_dir):
		return ""
	var logs: Array[String] = []
	for file_name: String in DirAccess.get_files_at(log_dir):
		if file_name.begins_with("run_") and file_name.ends_with(".json"):
			logs.append(file_name)
	if logs.is_empty():
		return ""
	logs.sort()
	return "%s/%s" % [log_dir, logs[-1]]


func copy_report(report: Dictionary) -> void:
	DisplayServer.clipboard_set(format_report(report))


## Cuantos reportes hay sin mandar. El panel lo muestra para que la carpeta no
## sea un lugar donde las cosas se pierden en silencio.
func count_saved_reports() -> int:
	if not DirAccess.dir_exists_absolute(FEEDBACK_DIR):
		return 0
	var names: PackedStringArray = DirAccess.get_files_at(FEEDBACK_DIR)
	return names.size()


## Que arena se esta jugando, para que el reporte lo diga sin preguntarlo.
func set_arena_name(arena_name: String) -> void:
	_arena_name = arena_name
