class_name SettingsScreen
extends Control
## The options screen, built from a schema rather than by hand.
##
## SettingsManager already owned every value, every default and the code to apply
## and persist them - what was missing was any way for a player to reach it. All of
## it was unreachable: sensitivity, FOV, volumes, the accessibility switches.
##
## The rows are generated from SCHEMA instead of authored in the .tscn because a
## hand-built panel of twenty-odd controls drifts from the backend the moment a
## setting is added: the value exists, nothing shows it, and nobody notices. Here a
## new setting is one row, and if the key is missing from DEFAULTS the build fails
## a test rather than shipping a control wired to nothing.
##
## Changes apply immediately - you cannot judge a sensitivity or a volume from a
## number - and persist when the screen closes.

signal closed()

## Order is the order on screen. `key` must exist in SettingsManager.DEFAULTS.
const SCHEMA: Array = [
	{"section": "INPUT"},
	{"key": "input/mouse_sensitivity", "label": "Mouse sensitivity",
		"type": "slider", "min": 0.1, "max": 10.0, "step": 0.05},
	{"key": "input/ads_sensitivity_multiplier", "label": "ADS sensitivity",
		"type": "slider", "min": 0.1, "max": 2.0, "step": 0.01},
	{"key": "input/invert_y", "label": "Invert vertical look", "type": "toggle"},

	{"section": "VIDEO"},
	{"key": "video/fov", "label": "Field of view",
		"type": "slider", "min": 70.0, "max": 120.0, "step": 1.0, "suffix": "°"},
	{"key": "video/fullscreen", "label": "Fullscreen", "type": "toggle"},
	{"key": "video/vsync", "label": "V-Sync", "type": "toggle"},
	{"key": "video/fps_cap", "label": "Frame rate cap", "type": "option",
		"choices": [["60 FPS", 60], ["120 FPS", 120], ["144 FPS", 144],
			["240 FPS", 240], ["Uncapped", 0]]},

	{"section": "AUDIO"},
	{"key": "audio/master_volume", "label": "Master", "type": "percent"},
	{"key": "audio/sfx_volume", "label": "Effects", "type": "percent"},
	{"key": "audio/music_volume", "label": "Music", "type": "percent"},
	{"key": "audio/vo_volume", "label": "Announcer", "type": "percent"},

	{"section": "ACCESSIBILITY"},
	{"key": "accessibility/screenshake_enabled", "label": "Screen shake", "type": "toggle"},
	{"key": "accessibility/view_bob_enabled", "label": "View bob", "type": "toggle"},
	{"key": "accessibility/motion_blur_enabled", "label": "Motion blur", "type": "toggle"},
	{"key": "accessibility/subtitles_enabled", "label": "Subtitles", "type": "toggle"},
	{"key": "accessibility/subtitle_size", "label": "Subtitle size", "type": "option",
		"choices": [["Small", 0], ["Medium", 1], ["Large", 2]]},
	{"key": "accessibility/reduce_flashing", "label": "Reduce flashing", "type": "toggle"},

	{"section": "HUD"},
	{"key": "hud/scale", "label": "HUD scale",
		"type": "slider", "min": 0.75, "max": 1.5, "step": 0.05},
	{"key": "hud/crosshair_gap", "label": "Crosshair gap",
		"type": "slider", "min": 0.0, "max": 24.0, "step": 1.0},
	{"key": "hud/crosshair_thickness", "label": "Crosshair thickness",
		"type": "slider", "min": 1.0, "max": 6.0, "step": 0.5},
	{"key": "hud/crosshair_dot", "label": "Centre dot", "type": "toggle"},
	{"key": "hud/crosshair_color", "label": "Crosshair colour", "type": "color"},
	{"key": "hud/damage_indicators", "label": "Damage indicators", "type": "toggle"},
]

const ROW_CONTROL_WIDTH: int = 260

@onready var _rows: VBoxContainer = $Panel/Margin/Layout/Scroll/Rows
@onready var _back_button: Button = $Panel/Margin/Layout/Footer/BackButton
@onready var _reset_button: Button = $Panel/Margin/Layout/Footer/ResetButton

## key -> the control showing it, so a reset can refresh every row in place.
var _controls: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()
	_back_button.pressed.connect(close)
	_reset_button.pressed.connect(_on_reset_pressed)


## `_input` rather than `_unhandled_input`: this has to beat GameManager to the
## escape key, or closing the options would also unpause the match underneath.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# Public API

func open() -> void:
	_refresh_all()
	visible = true
	_back_button.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	SettingsManager.save_settings()
	closed.emit()


# Private

func _build() -> void:
	for entry: Dictionary in SCHEMA:
		if entry.has("section"):
			_rows.add_child(_make_section(String(entry["section"])))
			continue
		_rows.add_child(_make_row(entry))


func _make_section(title: String) -> Control:
	var label := Label.new()
	label.theme_type_variation = &"HUDLabel"
	label.text = title
	label.add_theme_color_override(&"font_color", Tokens.PLAYER)
	label.add_theme_constant_override(&"line_spacing", 0)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_top", 18)
	margin.add_theme_constant_override(&"margin_bottom", 4)
	margin.add_child(label)
	return margin


func _make_row(entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)

	var label := Label.new()
	label.text = String(entry["label"])
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	var control: Control = _make_control(entry)
	control.custom_minimum_size = Vector2(ROW_CONTROL_WIDTH, 0)
	row.add_child(control)
	_controls[String(entry["key"])] = control
	return row


func _make_control(entry: Dictionary) -> Control:
	match String(entry["type"]):
		"toggle":
			return _make_toggle(entry)
		"option":
			return _make_option(entry)
		"color":
			return _make_color(entry)
		"percent":
			return _make_slider(entry, 0.0, 1.0, 0.01, true)
	return _make_slider(entry, float(entry["min"]), float(entry["max"]),
		float(entry["step"]), false)


## Slider plus a live readout: a number with no value beside it is unusable, and a
## value with no number cannot be reported in a bug.
func _make_slider(entry: Dictionary, minimum: float, maximum: float, step: float,
		as_percent: bool) -> Control:
	var key: String = String(entry["key"])
	var box := HBoxContainer.new()
	box.add_theme_constant_override(&"separation", 12)

	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = float(SettingsManager.get_value(key))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(slider)

	var readout := Label.new()
	readout.theme_type_variation = &"Keybind"
	readout.custom_minimum_size = Vector2(56, 0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(readout)

	var suffix: String = String(entry.get("suffix", ""))
	var write := func(value: float) -> void:
		readout.text = ("%d%%" % roundi(value * 100.0)) if as_percent \
			else ("%s%s" % [String.num(value, 2 if step < 1.0 else 0), suffix])
	write.call(slider.value)
	slider.value_changed.connect(func(value: float) -> void:
		write.call(value)
		_commit(key, value))

	box.set_meta(&"slider", slider)
	box.set_meta(&"write", write)
	return box


func _make_toggle(entry: Dictionary) -> Control:
	var key: String = String(entry["key"])
	var button := CheckButton.new()
	button.button_pressed = bool(SettingsManager.get_value(key))
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	button.toggled.connect(func(pressed: bool) -> void: _commit(key, pressed))
	return button


func _make_option(entry: Dictionary) -> Control:
	var key: String = String(entry["key"])
	var button := OptionButton.new()
	var current: int = int(SettingsManager.get_value(key))
	var choices: Array = entry["choices"]
	for index: int in choices.size():
		var choice: Array = choices[index]
		button.add_item(String(choice[0]), index)
		button.set_item_metadata(index, int(choice[1]))
		if int(choice[1]) == current:
			button.select(index)
	button.item_selected.connect(func(index: int) -> void:
		_commit(key, int(button.get_item_metadata(index))))
	return button


func _make_color(entry: Dictionary) -> Control:
	var key: String = String(entry["key"])
	var picker := ColorPickerButton.new()
	picker.color = SettingsManager.get_value(key)
	picker.edit_alpha = false
	picker.custom_minimum_size = Vector2(0, 30)
	picker.color_changed.connect(func(colour: Color) -> void: _commit(key, colour))
	return picker


## Applied on every change rather than on confirm. The whole point of a sensitivity
## or a volume is that it cannot be judged from its number, and the tree is paused
## while this is open, so re-applying costs nothing worth saving.
func _commit(key: String, value: Variant) -> void:
	SettingsManager.set_value(key, value)
	SettingsManager.apply_all()


func _refresh_all() -> void:
	for entry: Dictionary in SCHEMA:
		if entry.has("section"):
			continue
		var key: String = String(entry["key"])
		var control: Control = _controls.get(key)
		if control == null:
			continue
		var value: Variant = SettingsManager.get_value(key)
		if control is CheckButton:
			(control as CheckButton).button_pressed = bool(value)
		elif control is ColorPickerButton:
			(control as ColorPickerButton).color = value
		elif control is OptionButton:
			var option := control as OptionButton
			for index: int in option.item_count:
				if int(option.get_item_metadata(index)) == int(value):
					option.select(index)
					break
		elif control.has_meta(&"slider"):
			var slider: HSlider = control.get_meta(&"slider")
			slider.set_value_no_signal(float(value))
			var write: Callable = control.get_meta(&"write")
			write.call(float(value))


func _on_reset_pressed() -> void:
	SettingsManager.reset_to_defaults()
	_refresh_all()
