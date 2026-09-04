@tool
class_name BalanceDock
extends VBoxContainer
## The Balance Editor: economy on one tab, the archetypes on the other, and the
## projected economy curve under both.
##
## Every field here writes straight into the resource the game loads. Saving is
## what makes it live - `BalanceHub` in the running game notices the file and
## reloads it in place.

const SKILL_LABEL: String = "Projected skill: %d%%"

var model := BalanceModel.new()

var _tabs: TabContainer
var _economy_tab: VBoxContainer
var _enemy_tab: VBoxContainer
var _chart: EconomyCurveChart
var _skill_slider: HSlider
var _skill_label: Label
var _preset_button: OptionButton
var _preset_name: LineEdit
var _status: Label
var _preset_paths: PackedStringArray = PackedStringArray()


func _ready() -> void:
	name = "Balance"
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(0.0, 260.0)
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_economy_tab = _make_tab("Economy")
	_enemy_tab = _make_tab("Archetypes")
	add_child(_tabs)

	_chart = EconomyCurveChart.new()
	add_child(_chart)
	_build_skill_row()
	_build_preset_row()
	_status = Label.new()
	add_child(_status)

	model.changed.connect(_refresh_chart)
	model.load_all()
	_build_economy_fields()
	_build_enemy_fields()
	_refresh_presets()
	_refresh_chart()


# Private

func _make_tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	_tabs.add_child(scroll)
	return box


func _build_economy_fields() -> void:
	if model.economy == null:
		_set_status("No economy config at %s." % BalanceModel.ECONOMY_PATH)
		return
	for property: Dictionary in model.economy.get_property_list():
		var property_name: String = property["name"]
		var type: int = int(property["type"])
		if int(property["usage"]) & PROPERTY_USAGE_EDITOR == 0:
			continue
		if type != TYPE_INT and type != TYPE_FLOAT:
			continue
		var on_changed: Callable = _make_economy_setter(StringName(property_name), type == TYPE_INT)
		_economy_tab.add_child(_number_row(property_name.capitalize(),
			float(model.economy.get(property_name)), type == TYPE_INT, on_changed))


func _build_enemy_fields() -> void:
	for enemy: EnemyData in model.enemies:
		var header := Label.new()
		header.text = "%s  (%s)" % [enemy.display_name, enemy.id]
		_enemy_tab.add_child(header)
		for field: StringName in BalancePreset.ENEMY_FIELDS:
			_enemy_tab.add_child(_number_row("    %s" % String(field).capitalize(),
				float(enemy.get(field)), false, _make_enemy_setter(enemy, field)))
		_enemy_tab.add_child(HSeparator.new())


## Built here rather than inline so each row closes over its own field instead of
## the loop variable every row would otherwise share.
func _make_economy_setter(field: StringName, is_int: bool) -> Callable:
	return func(value: float) -> void:
		model.economy.set(field, int(value) if is_int else value)
		_refresh_chart()


func _make_enemy_setter(enemy: EnemyData, field: StringName) -> Callable:
	return func(value: float) -> void:
		enemy.set(field, value)


func _number_row(label_text: String, value: float, is_int: bool,
		on_changed: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(220.0, 0.0)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = -10000.0
	spin.max_value = 100000.0
	spin.step = 1.0 if is_int else 0.05
	spin.value = value
	spin.value_changed.connect(on_changed)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)
	return row


func _build_skill_row() -> void:
	var row := HBoxContainer.new()
	_skill_label = Label.new()
	_skill_label.custom_minimum_size = Vector2(160.0, 0.0)
	row.add_child(_skill_label)
	_skill_slider = HSlider.new()
	_skill_slider.min_value = 0.0
	_skill_slider.max_value = 1.0
	_skill_slider.step = 0.05
	_skill_slider.value = 0.75
	_skill_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_slider.value_changed.connect(func(_value: float) -> void: _refresh_chart())
	row.add_child(_skill_slider)
	add_child(row)


func _build_preset_row() -> void:
	var row := HBoxContainer.new()
	_preset_button = OptionButton.new()
	_preset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_preset_button)
	row.add_child(_button("Load preset", _on_load_preset))
	_preset_name = LineEdit.new()
	_preset_name.placeholder_text = "preset name"
	row.add_child(_preset_name)
	row.add_child(_button("Save preset", _on_save_preset))
	row.add_child(_button("Reload", _on_reload))
	row.add_child(_button("Apply to game", _on_apply))
	add_child(row)


func _on_reload() -> void:
	model.load_all()
	_set_status("Reloaded from disk.")


func _on_apply() -> void:
	var result: Error = model.save_all()
	if result == OK:
		_set_status("Saved. A running editor build picks it up within half a second.")
	else:
		_set_status("Save failed (%d)." % result)


func _on_save_preset() -> void:
	var preset_name: String = _preset_name.text.strip_edges()
	if preset_name == "":
		_set_status("Name the preset first.")
		return
	var preset: BalancePreset = BalancePreset.capture(model, preset_name)
	var path: String = BalancePreset.PRESET_DIR.path_join("%s.tres" % preset_name.to_snake_case())
	var result: Error = ResourceSaver.save(preset, path)
	if result == OK:
		_set_status("Saved preset %s" % path.get_file())
	else:
		_set_status("Preset save failed (%d)." % result)
	_refresh_presets()


func _on_load_preset() -> void:
	var index: int = _preset_button.get_selected_id()
	if index < 0 or index >= _preset_paths.size():
		return
	var preset := load(_preset_paths[index]) as BalancePreset
	if preset == null:
		_set_status("That preset would not load.")
		return
	preset.apply(model)
	_refresh_chart()
	_set_status("Applied preset '%s'. Press Apply to game to write it." % preset.preset_name)


func _refresh_presets() -> void:
	_preset_paths = BalancePreset.list_presets()
	_preset_button.clear()
	for index: int in _preset_paths.size():
		_preset_button.add_item(_preset_paths[index].get_file().get_basename(), index)


func _refresh_chart() -> void:
	if _chart == null:
		return
	_skill_label.text = SKILL_LABEL % int(round(_skill_slider.value * 100.0))
	_chart.set_data(
		CurveEvaluator.cumulative_series(model.waves, model.economy, _skill_slider.value),
		CurveEvaluator.price_ladder(model.shop))


func _button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(handler)
	return button


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text
