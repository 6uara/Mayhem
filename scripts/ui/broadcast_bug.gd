class_name BroadcastBug
extends Control
## The Host's persistent broadcast layer: a 4px amber top edge, a LIVE tag and the
## crossed-ring mark.
##
## The handoff's decision is that the Host is heard, never seen - no portrait, no
## face, because a portrait would cost character art and would make him smaller than
## he sounds. Instead he owns transmission equipment at the edge of every frame,
## which is the colosseum-owner fantasy for the price of three UI elements.

@export var mark_color: Color = Color("#FFB020")
@export var live_dot_color: Color = Color("#FF3B54")

var _tag: Label
var _mark: HostMark


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	offset_bottom = 80.0
	_build()
	EventBus.wave_started.connect(_on_wave_started.unbind(1))
	_refresh_tag()


func _draw() -> void:
	# The amber top edge. Present on every screen, never in the way.
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, Tokens.BUG_EDGE_HEIGHT)), mark_color)


# Private

func _build() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	row.offset_left = -260.0
	row.offset_top = 18.0
	row.offset_right = -Tokens.SCREEN_MARGIN
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	var dot := ColorRect.new()
	dot.color = live_dot_color
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)

	_tag = Label.new()
	_tag.theme_type_variation = &"Keybind"
	_tag.add_theme_color_override("font_color", mark_color)
	row.add_child(_tag)

	_mark = HostMark.new()
	_mark.color = mark_color
	_mark.custom_minimum_size = Vector2(28, 28)
	_mark.modulate.a = Tokens.BUG_MARK_ALPHA
	row.add_child(_mark)


## El numero sale de la señal y no de `WaveManager.current_index`.
##
## Los dos dicen lo mismo mientras nadie se equivoque, y ese es justamente el
## problema: eran dos lecturas del mismo hecho desde dos fuentes, y el cluster de
## oleada -que si usa el parametro- podia terminar mostrando un numero distinto
## al de este cartel. Dos numeros de oleada en pantalla que no coinciden es peor
## que no mostrar ninguno.
func _on_wave_started(wave_index: int) -> void:
	_refresh_tag(wave_index + 1)


func _refresh_tag(wave: int = -1) -> void:
	if _tag == null:
		return
	# Sin señal todavia -la primera pintada, antes de que arranque la oleada 1-
	# se cae a lo que sepa WaveManager, que es lo unico que hay a esa altura.
	if wave < 0:
		wave = WaveManager.current_index + 1
	_tag.text = "LIVE - WAVE %02d" % maxi(wave, 1)
