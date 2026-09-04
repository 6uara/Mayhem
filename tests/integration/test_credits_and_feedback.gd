extends GutTest
## Los creditos y el formulario de feedback: las dos pantallas que faltaban para
## poder publicar.
##
## Los creditos no son cortesia - las licencias MIT y OFL que usa el juego exigen
## atribucion, y la pagina de Steam la pide. El feedback tampoco es un extra: sin
## el, lo unico que llega de un playtest es lo que el jugador se acuerde de
## contar despues.

const MENU_SCENE: String = "res://scenes/main/main_menu.tscn"
const PAUSE_SCENE: String = "res://scenes/ui/pause_menu.tscn"

var _menu: Control


func before_each() -> void:
	_menu = add_child_autofree(load(MENU_SCENE).instantiate())
	await wait_frames(2)


func _panel(path: String) -> Control:
	return _menu.get_node(path)


# --------------------------------------------------------------- creditos

func test_the_menu_has_a_way_into_the_credits() -> void:
	var credits: CreditsPanel = _panel("Credits")
	_panel("Root/Panel/Margin/Layout/CreditsButton").pressed.emit()
	await wait_frames(2)

	assert_true(credits.visible)
	assert_false(_panel("Root").visible, "el panel reemplaza al menu, no se apila")
	credits.close()
	await wait_frames(2)
	assert_true(_panel("Root").visible, "y volver aterriza en el menu")


## Cada dependencia con licencia que exige atribucion tiene que estar nombrada.
## Si entra una nueva y nadie toca `SECTIONS`, esto se cae.
func test_every_licensed_dependency_is_named() -> void:
	var text: String = ""
	for section: Dictionary in CreditsPanel.SECTIONS:
		for line: Array in section["lines"]:
			text += "%s %s " % [line[0], line[1]]
	for required: String in ["Godot", "Beehave", "IBM Plex", "Archivo",
			"MIT License", "SIL Open Font License"]:
		assert_string_contains(text, required)


func test_the_credits_list_is_built_from_the_data() -> void:
	var credits: CreditsPanel = _panel("Credits")
	credits.open()
	await wait_frames(2)
	var sections: VBoxContainer = _panel("Credits/Panel/Margin/Layout/Scroll/Sections")
	assert_gt(sections.get_child_count(), CreditsPanel.SECTIONS.size(),
		"un titulo por seccion y una fila por linea, nada autorado a mano")


# --------------------------------------------------------------- feedback

func test_the_menu_has_a_way_into_the_feedback_form() -> void:
	var feedback: FeedbackPanel = _panel("Feedback")
	_panel("Root/Panel/Margin/Layout/FeedbackButton").pressed.emit()
	await wait_frames(2)
	assert_true(feedback.visible)
	feedback.close()


## El que importa: se reporta durante la run, no al final.
func test_the_pause_menu_can_report_mid_run() -> void:
	var pause: CanvasLayer = add_child_autofree(load(PAUSE_SCENE).instantiate())
	await wait_frames(2)
	var feedback: FeedbackPanel = pause.get_node("Feedback")
	pause.get_node("Root/Panel/Margin/Layout/FeedbackButton").pressed.emit()
	await wait_frames(2)
	assert_true(feedback.visible)
	feedback.close()


## Lo que hace util a un reporte es el contexto, y el contexto escrito a mano no
## llega: nadie anota la version, la wave ni su GPU.
func test_a_report_carries_the_context_nobody_would_type() -> void:
	var report: Dictionary = FeedbackManager.build_report("se traba en la wave 3", "Bug")
	for key: String in ["version", "date", "wave", "os", "gpu", "resolution", "fps",
			"session_seconds", "arena", "score"]:
		assert_true(report.has(key), "falta %s" % key)
	assert_eq(String(report["body"]), "se traba en la wave 3")
	assert_eq(String(report["category"]), "Bug")


func test_the_markdown_is_pasteable() -> void:
	var text: String = FeedbackManager.format_report(
		FeedbackManager.build_report("algo", "Idea"))
	assert_string_contains(text, "MAYHEM feedback - Idea")
	assert_string_contains(text, "algo")
	assert_string_contains(text, "- version:")


func test_a_saved_report_lands_in_a_file() -> void:
	var report: Dictionary = FeedbackManager.build_report("probando", "Other")
	var path: String = FeedbackManager.save_report(report)
	assert_ne(path, "", "tiene que decir donde quedo")
	assert_true(FileAccess.file_exists(path))

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	DirAccess.remove_absolute(path)
	assert_true(parsed is Dictionary)
	assert_eq(String((parsed as Dictionary)["body"]), "probando")


## Sin formulario configurado el boton no aparece, en vez de aparecer y no hacer
## nada cuando lo apretas.
func test_the_form_button_only_exists_when_there_is_a_form() -> void:
	var feedback: FeedbackPanel = _panel("Feedback")
	var button: Button = _panel("Feedback/Panel/Margin/Layout/Footer/FormButton") as Button
	assert_eq(button.visible, FeedbackManager.has_form())
	assert_false(feedback.visible, "y el panel arranca cerrado")


## Nada sale de la maquina solo, y el panel lo dice.
func test_the_panel_states_what_it_attaches() -> void:
	var privacy: Label = _panel("Feedback/Panel/Margin/Layout/Privacy") as Label
	assert_string_contains(privacy.text, "GPU")
	assert_string_contains(privacy.text, "Nothing is sent anywhere on its own")
