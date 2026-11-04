class_name KeyCap
extends Control
## Una tecla dibujada: lo que el tutorial le muestra al jugador en vez de pedirle
## que lea el nombre de la tecla en una frase.
##
## Se lee del InputMap, con el dispositivo que se este usando, asi que un rebind
## o agarrar el joystick no la dejan mintiendo. Los botones del mouse son un mouse
## con el boton encendido: "Left Mouse" se lee, un dibujo se ve de reojo.
##
## Tres estados que se distinguen por algo mas que el color (la ley de `Tokens`):
## apagada, pedida (borde que late) y apretada o cumplida (rellena).

## Si es la tecla que el paso esta pidiendo ahora. Las demas quedan apagadas.
var is_asked: bool = false:
	set(value):
		is_asked = value
		_set_pulsing(value and not _is_done)
		queue_redraw()

var _action: StringName = &""
var _text: String = ""
var _mouse_button: MouseButton = MOUSE_BUTTON_NONE
var _font: Font
var _is_held: bool = false
var _is_done: bool = false
## Brillo del borde mientras esta pedida, de 1 para abajo. Ver _set_pulsing().
var _pulse: float = 1.0:
	set(value):
		_pulse = value
		queue_redraw()
var _pulse_tween: Tween


func setup(action: StringName) -> KeyCap:
	_action = action
	_font = load(Tokens.FONT_MONO)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var event: InputEvent = TutorialHintManager.prompt_event(action)
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		_mouse_button = mouse.button_index
		custom_minimum_size = Vector2(Tokens.KEY_CAP_MOUSE_W, Tokens.KEY_CAP_H)
		return self
	_text = SettingsManager.describe_event(event).to_upper() if event != null else "?"
	var width: float = _font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		Tokens.SIZE_LABEL).x + Tokens.KEY_CAP_PADDING * 2.0
	custom_minimum_size = Vector2(maxf(width, Tokens.KEY_CAP_H), Tokens.KEY_CAP_H)
	return self


func _ready() -> void:
	# El jugador puede llegar a este paso con la tecla ya apretada.
	_is_held = InputMap.has_action(_action) and Input.is_action_pressed(_action)
	# `is_asked` pudo asignarse antes de entrar al arbol, donde no hay tweens.
	_set_pulsing(is_asked and not _is_done)


## Por evento y no preguntando cada frame, como todo en la HUD. Responde a la tecla
## aunque la accion todavia no se pueda hacer: es lo que le dice al jugador que
## encontro la correcta.
func _input(event: InputEvent) -> void:
	if not event.is_action(_action) or event.is_echo():
		return
	var held: bool = event.is_pressed()
	if held != _is_held:
		_is_held = held
		queue_redraw()


func mark_done() -> void:
	_is_done = true
	_set_pulsing(false)
	queue_redraw()
	UiMotion.punch(self)


func get_label() -> String:
	return _text


func is_mouse_glyph() -> bool:
	return _mouse_button != MOUSE_BUTTON_NONE


func is_lit() -> bool:
	return _is_held or _is_done


func _set_pulsing(on: bool) -> void:
	if _pulse_tween != null:
		_pulse_tween.kill()
		_pulse_tween = null
	_pulse = 1.0
	# Reducir destellos deja el borde encendido, quieto: la informacion sigue ahi.
	if not on or not is_inside_tree() or UiMotion.reduce_flashing():
		return
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(self, ^"_pulse", 0.35, Tokens.KEY_CAP_PULSE * 0.5)
	_pulse_tween.tween_property(self, ^"_pulse", 1.0, Tokens.KEY_CAP_PULSE * 0.5)


func _draw() -> void:
	var outline: PackedVector2Array = _outline()
	var lit: bool = is_lit()
	var border: Color = Tokens.LINE
	if lit:
		border = Tokens.PLAYER
	elif is_asked:
		border = Color(Tokens.PLAYER, _pulse)
	if is_mouse_glyph():
		draw_colored_polygon(outline, Tokens.RAISED)
		_draw_mouse_buttons(lit)
	else:
		draw_colored_polygon(outline, Tokens.PLAYER if lit else Tokens.RAISED)
		_draw_label(lit)
	outline.append(outline[0])
	draw_polyline(outline, border, Tokens.KEY_CAP_BORDER)


## El corte a 45 grados abajo a la derecha, el mismo de todos los paneles.
func _outline() -> PackedVector2Array:
	var cut: float = Tokens.KEY_CAP_CHAMFER
	return PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0.0),
		Vector2(size.x, size.y - cut), Vector2(size.x - cut, size.y), Vector2(0.0, size.y)])


func _draw_label(lit: bool) -> void:
	var tint: Color = Tokens.MUTED
	if lit:
		tint = Tokens.VOID
	elif is_asked:
		tint = Tokens.TEXT
	var ascent: float = _font.get_ascent(Tokens.SIZE_LABEL)
	var height: float = _font.get_height(Tokens.SIZE_LABEL)
	draw_string(_font, Vector2(0.0, (size.y - height) * 0.5 + ascent), _text,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, Tokens.SIZE_LABEL, tint)


func _draw_mouse_buttons(lit: bool) -> void:
	var half: float = size.x * 0.5
	var split: float = size.y * 0.45
	var tint: Color = Tokens.DIM
	if lit:
		tint = Tokens.PLAYER
	elif is_asked:
		tint = Color(Tokens.PLAYER, _pulse)
	var left: float = 0.0 if _mouse_button == MOUSE_BUTTON_LEFT else half
	draw_rect(Rect2(left, 0.0, half, split), tint)
	draw_line(Vector2(0.0, split), Vector2(size.x, split), Tokens.LINE, Tokens.KEY_CAP_BORDER)
	draw_line(Vector2(half, 0.0), Vector2(half, split), Tokens.LINE, Tokens.KEY_CAP_BORDER)
