class_name FeedbackPanel
extends Control
## El formulario de feedback, desde el menu y desde la pausa.
##
## Desde la pausa sobre todo: el momento en que algo molesta es durante la run,
## y un reporte que hay que acordarse de escribir al final no se escribe.
##
## Tres salidas, y ninguna manda nada sola: guardar deja el archivo en
## `user://feedback/`, copiar deja el reporte en el portapapeles listo para
## pegar, y el formulario abre el navegador. Lo que se adjunta esta escrito en
## pantalla, porque adjuntar datos de la maquina de alguien sin decirselo no se
## hace.

signal closed()

@onready var _category: OptionButton = $Panel/Margin/Layout/Category
@onready var _body: TextEdit = $Panel/Margin/Layout/Body
@onready var _privacy: Label = $Panel/Margin/Layout/Privacy
@onready var _status: Label = $Panel/Margin/Layout/Status
@onready var _save_button: Button = $Panel/Margin/Layout/Footer/SaveButton
@onready var _copy_button: Button = $Panel/Margin/Layout/Footer/CopyButton
@onready var _form_button: Button = $Panel/Margin/Layout/Footer/FormButton
@onready var _back_button: Button = $Panel/Margin/Layout/Footer/BackButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	for category: String in FeedbackManager.get_categories():
		_category.add_item(category)
	if _category.item_count > 0:
		_category.select(0)
	_privacy.text = "Attached automatically: version, arena, wave, score, session length, OS, GPU, resolution and FPS. Nothing is sent anywhere on its own."
	_save_button.pressed.connect(_on_save_pressed)
	_copy_button.pressed.connect(_on_copy_pressed)
	_form_button.pressed.connect(_on_form_pressed)
	_back_button.pressed.connect(close)
	_form_button.visible = FeedbackManager.has_form()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	# Escribiendo en el cuerpo, escape tiene que salir del campo y no del panel.
	if _body.has_focus():
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# Public API

func open() -> void:
	visible = true
	_status.text = ""
	_body.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


# Private

func _report() -> Dictionary:
	var category: String = _category.get_item_text(maxi(_category.selected, 0)) \
		if _category.item_count > 0 else "Other"
	return FeedbackManager.build_report(_body.text, category)


## Un reporte vacio no es un reporte. Se avisa en vez de escribir un archivo que
## no dice nada.
func _has_body() -> bool:
	if _body.text.strip_edges() != "":
		return true
	_status.text = "Write something first."
	return false


func _on_save_pressed() -> void:
	if not _has_body():
		return
	var path: String = FeedbackManager.save_report(_report())
	_status.text = "Saved to %s" % path if path != "" else "Could not write the file."


func _on_copy_pressed() -> void:
	if not _has_body():
		return
	FeedbackManager.copy_report(_report())
	_status.text = "Copied. Paste it wherever you like."


func _on_form_pressed() -> void:
	if not _has_body():
		return
	FeedbackManager.copy_report(_report())
	if FeedbackManager.open_form():
		_status.text = "Copied and opened the form - paste it there."
		return
	_status.text = "No form configured in this build."
