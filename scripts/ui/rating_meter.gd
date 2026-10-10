class_name RatingMeter
extends VBoxContainer
## El rating de la transmision en la HUD: el escalon, el multiplicador y una barra.
##
## Va debajo de la plata porque es lo que la multiplica: leer "x1.6" al lado del
## numero que crece es lo que enseña que el estilo paga. Ambar por la misma razon
## que el borde de la transmision: el rating es de la casa, no del jugador.

const BAR_SIZE: Vector2 = Vector2(180.0, 4.0)

var _label: Label
var _bar_back: ColorRect
var _bar_fill: ColorRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 4)
	_label = Label.new()
	_label.theme_type_variation = &"HUDLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_color_override("font_color", Tokens.REWARD)
	add_child(_label)
	_bar_back = ColorRect.new()
	_bar_back.color = Tokens.LINE
	_bar_back.custom_minimum_size = BAR_SIZE
	_bar_back.size_flags_horizontal = Control.SIZE_SHRINK_END
	_bar_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar_back)
	_bar_fill = ColorRect.new()
	_bar_fill.color = Tokens.REWARD
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_back.add_child(_bar_fill)
	BroadcastRating.changed.connect(_on_changed)
	_on_changed(BroadcastRating.value, BroadcastRating.get_tier())


## Lo que dice el texto ahora mismo; para los tests.
func get_text() -> String:
	return _label.text


func _on_changed(value: float, tier: int) -> void:
	_label.text = "%s  x%.1f" % [BroadcastRating.get_tier_name(tier),
		BroadcastRating.get_multiplier()]
	_bar_fill.size = Vector2(BAR_SIZE.x * clampf(value / BroadcastRating.MAX_VALUE, 0.0, 1.0),
		BAR_SIZE.y)
	modulate.a = 0.55 if value <= 0.0 else 1.0
