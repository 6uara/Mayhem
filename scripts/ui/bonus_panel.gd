class_name BonusPanel
extends Control
## The bonus badge on the HUD, and the list it unfolds into.
##
## Collapsed it is a glyph and a count on the left edge, outside the no-UI zone -
## small enough to ignore while shooting, loud enough to remember the bonuses
## exist. Held or toggled with `toggle_bonuses` (O by default) it unfolds the
## full categorised list, because "what am I actually running" is a question that
## comes up mid-fight and should not cost a trip to the shop to answer.

## Seconds the list takes to unfold. Short: this is a glance, not a screen.
const SLIDE_TIME: float = 0.12
## How often the temporary countdowns are rewritten while open.
const TICK_INTERVAL: float = 0.25

var is_open: bool = false

var _badge: PanelContainer
var _count_label: Label
var _hint_label: Label
var _list_panel: PanelContainer
var _list: BonusList
var _tween: Tween
var _tick: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	UpgradeManager.upgrades_changed.connect(_refresh_badge)
	# The shop lists the same bonuses in full while it is up; two copies of the
	# list on one screen is noise, so the HUD one stands down.
	EventBus.shop_opened.connect(_on_shop_opened)
	EventBus.shop_closed.connect(_on_shop_closed)
	_refresh_badge()
	set_process(false)


## Unhandled so the key never steals input from a menu that is already up.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_bonuses"):
		toggle()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_tick += delta
	if _tick < TICK_INTERVAL:
		return
	_tick = 0.0
	_list.tick_timers()


func toggle() -> void:
	set_open(not is_open)


func set_open(open: bool) -> void:
	if open == is_open:
		return
	is_open = open
	if open:
		_list.refresh()
	set_process(open)
	if _tween != null and _tween.is_running():
		_tween.kill()
	_list_panel.visible = true
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_list_panel, "modulate:a", 1.0 if open else 0.0, SLIDE_TIME)
	_tween.parallel().tween_property(_list_panel, "position:x", 0.0 if open else -16.0, SLIDE_TIME)
	if not open:
		_tween.tween_callback(func() -> void: _list_panel.visible = false)


# Private

func _on_shop_opened() -> void:
	set_open(false)
	visible = false


func _on_shop_closed() -> void:
	visible = true


func _build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", Tokens.CLUSTER_GAP)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	_badge = PanelContainer.new()
	_badge.theme_type_variation = &"HUDPanel"
	_badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_row := HBoxContainer.new()
	badge_row.add_theme_constant_override("separation", 8)
	var glyph := MayhemIcon.new()
	glyph.kind = MayhemIcon.Kind.FRAME_SURVIVABILITY
	glyph.color = Tokens.PLAYER
	glyph.custom_minimum_size = Vector2(16, 16)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge_row.add_child(glyph)
	_count_label = Label.new()
	_count_label.theme_type_variation = &"NumSecond"
	_count_label.add_theme_color_override("font_color", Tokens.TEXT)
	badge_row.add_child(_count_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"HUDLabel"
	_hint_label.add_theme_color_override("font_color", Tokens.MUTED)
	_hint_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge_row.add_child(_hint_label)
	_badge.add_child(badge_row)
	column.add_child(_badge)

	_list_panel = PanelContainer.new()
	_list_panel.theme_type_variation = &"HUDPanel"
	_list_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_list_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list_panel.custom_minimum_size = Vector2(260, 0)
	_list_panel.visible = false
	_list_panel.modulate.a = 0.0
	_list_panel.position.x = -16.0
	_list = BonusList.new()
	_list_panel.add_child(_list)
	column.add_child(_list_panel)


func _refresh_badge() -> void:
	var entries: Array[Dictionary] = UpgradeManager.get_owned_entries()
	var total: int = 0
	for entry: Dictionary in entries:
		total += int(entry["stacks"])
	_count_label.text = str(total)
	_hint_label.text = "BONUSES  [%s]" % _binding_hint()
	# Nothing to show yet reads as dim, not as a broken widget.
	_badge.modulate.a = 1.0 if total > 0 else 0.55


## The key actually bound to the action, so a rebind does not leave the HUD
## telling the player to press O.
func _binding_hint() -> String:
	for event: InputEvent in InputMap.action_get_events(&"toggle_bonuses"):
		var key := event as InputEventKey
		if key != null:
			return OS.get_keycode_string(
				key.physical_keycode if key.physical_keycode != 0 else key.keycode)
	return "--"
