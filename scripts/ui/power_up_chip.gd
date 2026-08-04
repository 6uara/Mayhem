class_name PowerUpChip
extends PanelContainer
## One active temporary upgrade with its countdown.
##
## CLAUDE.md 5.5 requires temporary power-ups to show a countdown; the handoff gives
## it a triangle glyph, an acid right border and a depleting bar, so it reads as
## "borrowed time" rather than as another permanent stat.

var _data: UpgradeData
var _bar: ColorRect
var _seconds: Label


func _init() -> void:
	theme_type_variation = &"HUDPanel"


func setup(data: UpgradeData) -> void:
	_data = data
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var glyph := MayhemIcon.new()
	glyph.kind = MayhemIcon.Kind.POWER_UP
	glyph.color = Tokens.HAZARD
	glyph.custom_minimum_size = Vector2(16, 16)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(glyph)

	var name_label := Label.new()
	name_label.theme_type_variation = &"HUDLabel"
	name_label.text = data.display_name.to_upper()
	name_label.add_theme_color_override("font_color", Tokens.TEXT)
	row.add_child(name_label)

	_seconds = Label.new()
	_seconds.theme_type_variation = &"NumSecond"
	_seconds.add_theme_font_size_override("font_size", 20)
	_seconds.add_theme_color_override("font_color", Tokens.HAZARD)
	row.add_child(_seconds)
	column.add_child(row)

	var track := ColorRect.new()
	track.color = Tokens.RAISED
	track.custom_minimum_size = Vector2(Tokens.POWERUP_BAR_W, 3)
	_bar = ColorRect.new()
	_bar.color = Tokens.HAZARD
	_bar.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_bar.anchor_right = 1.0
	track.add_child(_bar)
	column.add_child(track)

	add_child(column)


func _process(_delta: float) -> void:
	if _data == null:
		return
	var remaining: float = UpgradeManager.get_temporary_remaining(_data.id)
	if remaining <= 0.0:
		queue_free()
		return
	_seconds.text = "%ds" % ceili(remaining)
	_bar.anchor_right = clampf(remaining / maxf(_data.duration, 0.01), 0.0, 1.0)
