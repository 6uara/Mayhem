class_name CreditsPanel
extends Control
## Quien hizo esto y sobre que esta hecho.
##
## El contenido sale de `SECTIONS` y no de labels autorados en el .tscn, por la
## misma razon por la que `SettingsScreen` sale de su `SCHEMA`: una pantalla de
## creditos escrita a mano se desincroniza de THIRD_PARTY.md la primera vez que
## entra una dependencia, y nadie se entera hasta que alguien reclama.
##
## No es solo cortesia. Las licencias MIT y OFL que usa el juego exigen
## atribucion, y la pagina de Steam la pide: esta pantalla es donde se cumple.

signal closed()

## Cada seccion es un titulo y sus lineas. Las lineas son [texto, detalle]: el
## texto es lo que se nombra y el detalle su licencia o su rol, que es lo que
## una atribucion tiene que decir para valer como tal.
const SECTIONS: Array = [
	{"title": "MAYHEM", "lines": [
		["Juan Guaragnini", "Design, code, art and audio"],
		["(c) 2026 Juan Guaragnini", "All rights reserved"],
	]},
	{"title": "BUILT WITH", "lines": [
		["Godot Engine 4.7", "MIT License - godotengine.org"],
		["Beehave 2.9.2", "MIT License - enemy behaviour trees"],
		["GUT", "MIT License - test framework (development only)"],
		["Phantom Camera", "MIT License (development only)"],
		["Debug Draw", "MIT License (development only)"],
	]},
	{"title": "TYPEFACES", "lines": [
		["IBM Plex Sans / Mono", "SIL Open Font License 1.1 - (c) 2017 IBM Corp."],
		["Archivo", "SIL Open Font License 1.1 - (c) Omnibus-Type"],
	]},
	{"title": "ASSETS", "lines": [
		["Models, textures and shaders", "Original to this project"],
		["Music and sound effects", "Original - procedurally generated placeholders"],
	]},
]

@onready var _sections: VBoxContainer = $Panel/Margin/Layout/Scroll/Sections
@onready var _version: Label = $Panel/Margin/Layout/Version
@onready var _back_button: Button = $Panel/Margin/Layout/Footer/BackButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_back_button.pressed.connect(close)
	_build()
	_version.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0.0.0")


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# Public API

func open() -> void:
	visible = true
	_back_button.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


# Private

func _build() -> void:
	for child: Node in _sections.get_children():
		child.queue_free()
	for section: Dictionary in SECTIONS:
		var heading := Label.new()
		heading.text = String(section["title"])
		heading.theme_type_variation = &"HUDLabel"
		_sections.add_child(heading)
		for line: Array in section["lines"]:
			_sections.add_child(_make_line(String(line[0]), String(line[1])))
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0.0, 14.0)
		_sections.add_child(spacer)


func _make_line(text: String, detail: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	var name_label := Label.new()
	name_label.text = text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_stretch_ratio = 1.0
	row.add_child(name_label)
	var detail_label := Label.new()
	detail_label.text = detail
	detail_label.theme_type_variation = &"HUDLabel"
	detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_label.size_flags_stretch_ratio = 1.6
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(detail_label)
	return row
