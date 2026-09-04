class_name ScoreEntryPanel
extends Control
## Le pregunta al jugador con que nombre queda anotada la run, y la anota.
##
## El puntaje se guardaba solo, en silencio, sin nombre y solo cuando se ganaba:
## la tabla era una lista de numeros anonimos que ademas casi nunca se llenaba.
## Este panel es el unico lugar que llama a `SaveManager.submit_score()`, asi que
## no hay forma de que una run quede anotada sin haber pasado por aca.
##
## Los nombres ya usados se ofrecen para elegir: con dos personas turnandose en
## la misma maquina, volver a tipear el nombre entero cada vez es la clase de
## friccion que termina en que todos los puntajes queden con el mismo nombre.

signal saved()

## Ultimo item del selector. Un id y no un indice porque la lista de perfiles
## cambia de largo y el "nuevo" siempre es el que esta abajo de todo.
const NEW_NAME_ID: int = -1

@onready var _summary: Label = $Panel/Margin/Layout/Summary
@onready var _profiles: OptionButton = $Panel/Margin/Layout/Profiles
@onready var _name_edit: LineEdit = $Panel/Margin/Layout/NameEdit
@onready var _hint: Label = $Panel/Margin/Layout/Hint
@onready var _save_button: Button = $Panel/Margin/Layout/Footer/SaveButton
@onready var _skip_button: Button = $Panel/Margin/Layout/Footer/SkipButton

var _score: int = 0
var _time: float = 0.0
var _waves: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_name_edit.max_length = SaveManager.NAME_MAX_LENGTH
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.text_submitted.connect(func(_text: String) -> void: _on_save_pressed())
	_profiles.item_selected.connect(_on_profile_selected)
	_save_button.pressed.connect(_on_save_pressed)
	_skip_button.pressed.connect(_on_skip_pressed)


# Public API

func open(score: int, total_time: float, waves_cleared: int) -> void:
	_score = score
	_time = total_time
	_waves = waves_cleared
	_summary.text = "%d points  -  %d waves  -  %s" % [
		score, waves_cleared, _format_time(total_time)]
	_rebuild_profiles()
	visible = true
	if _profiles.visible:
		_profiles.grab_focus()
	else:
		_name_edit.grab_focus()


# Private

## El selector solo aparece cuando hay algo que seleccionar. En una maquina
## nueva la primera run va directo al campo de texto, sin un desplegable de un
## solo item que no elige nada.
func _rebuild_profiles() -> void:
	_profiles.clear()
	var known: Array[String] = SaveManager.get_profiles()
	for index: int in known.size():
		_profiles.add_item(known[index], index)
	_profiles.visible = not known.is_empty()
	if known.is_empty():
		_name_edit.visible = true
		_name_edit.text = ""
		_update_validity()
		return
	_profiles.add_separator()
	_profiles.add_item("New name...", NEW_NAME_ID)
	_profiles.select(0)
	_on_profile_selected(0)


func _on_profile_selected(index: int) -> void:
	var is_new: bool = _profiles.get_item_id(index) == NEW_NAME_ID
	_name_edit.visible = is_new
	if is_new:
		_name_edit.text = ""
		_name_edit.grab_focus()
	_update_validity()


func _on_name_changed(_text: String) -> void:
	_update_validity()


## El boton se apaga en vez de aceptar y rechazar despues: el jugador tiene que
## ver que le falta mientras escribe, no despues de apretar.
func _update_validity() -> void:
	if not _name_edit.visible:
		_save_button.disabled = false
		_hint.text = ""
		return
	var valid: bool = SaveManager.is_valid_name(_name_edit.text)
	_save_button.disabled = not valid
	_hint.text = "" if valid else "%d to %d characters, letters and numbers." % [
		SaveManager.NAME_MIN_LENGTH, SaveManager.NAME_MAX_LENGTH]


func _chosen_name() -> String:
	if _name_edit.visible:
		return _name_edit.text
	if _profiles.selected < 0:
		return ""
	return _profiles.get_item_text(_profiles.selected)


func _on_save_pressed() -> void:
	_submit(_chosen_name())


## Saltar igual anota la run, con el nombre por defecto. Un puntaje perdido
## molesta mas que una fila que dice PLAYER, y el jugador que salta esta
## diciendo "no me importa el nombre", no "borrame la partida".
func _on_skip_pressed() -> void:
	_submit(SaveManager.DEFAULT_NAME)


func _submit(player_name: String) -> void:
	SaveManager.submit_score(_score, _time, _waves, player_name)
	visible = false
	saved.emit()


func _format_time(seconds: float) -> String:
	return "%d:%05.2f" % [int(seconds) / 60, fmod(seconds, 60.0)]
