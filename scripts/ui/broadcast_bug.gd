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
	EventBus.wave_started.connect(_on_wave_started.unbind(2))
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


func _on_wave_started() -> void:
	_refresh_tag()


func _refresh_tag() -> void:
	if _tag == null:
		return
	var wave: int = maxi(WaveManager.current_index + 1, 1)
	_tag.text = "LIVE - WAVE %02d" % wave
