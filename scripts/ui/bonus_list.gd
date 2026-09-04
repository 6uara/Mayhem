class_name BonusList
extends VBoxContainer
## The player's active bonuses, grouped by upgrade category.
##
## One widget, two homes: the in-match panel behind the O key and the shop's side
## column. Whatever the player is deciding - dodge into a fight or spend 300 on a
## second magazine - the answer needs the same list, so there is one of it.

## Category order, and the accent each one is drawn in. Mobility is the player's
## own colour, weapon reads as reward, survivability as the thing keeping you
## alive; the three are never the same hue as the enemy red.
const CATEGORY_ORDER: Array[int] = [
	UpgradeData.Category.MOBILITY,
	UpgradeData.Category.WEAPON,
	UpgradeData.Category.SURVIVABILITY,
]
const CATEGORY_TITLES: Dictionary = {
	UpgradeData.Category.MOBILITY: "MOBILITY",
	UpgradeData.Category.WEAPON: "WEAPON",
	UpgradeData.Category.SURVIVABILITY: "SURVIVABILITY",
}
const CATEGORY_COLORS: Dictionary = {
	UpgradeData.Category.MOBILITY: Tokens.PLAYER,
	UpgradeData.Category.WEAPON: Tokens.REWARD,
	UpgradeData.Category.SURVIVABILITY: Tokens.HEAL,
}
const CATEGORY_ICONS: Dictionary = {
	UpgradeData.Category.MOBILITY: MayhemIcon.Kind.FRAME_MOBILITY,
	UpgradeData.Category.WEAPON: MayhemIcon.Kind.FRAME_WEAPON,
	UpgradeData.Category.SURVIVABILITY: MayhemIcon.Kind.FRAME_SURVIVABILITY,
}

## Shown instead of an empty column, so "nothing yet" never reads as "broken".
const EMPTY_TEXT: String = "NO BONUSES YET"
## Categories with nothing in them are hidden by default; the shop shows them all
## so the three columns stay in the same place between visits.
@export var show_empty_categories: bool = false
## Lays the three categories side by side instead of stacked. The shop has width
## to spare and no height; the HUD panel is the other way around.
@export var horizontal: bool = false

var _entries: Array[Dictionary] = []
## Label -> entry, for the temporary bonuses whose countdown ticks while visible.
var _timer_labels: Dictionary = {}


func _ready() -> void:
	add_theme_constant_override("separation", Tokens.ROW_GAP)
	UpgradeManager.upgrades_changed.connect(refresh)
	refresh()


## Rebuilds from UpgradeManager. Cheap: this list is a handful of rows and only
## rebuilds when a purchase lands or the panel opens.
func refresh() -> void:
	# Removed, not just queued: a rebuild in the same frame (open the panel right
	# after a purchase) would otherwise count the old rows as still there.
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_entries = UpgradeManager.get_owned_entries()
	_timer_labels.clear()
	var container: BoxContainer = self
	if horizontal:
		container = HBoxContainer.new()
		container.add_theme_constant_override("separation", Tokens.PANEL_PADDING)
		add_child(container)
	var shown: int = 0
	for category: int in CATEGORY_ORDER:
		var rows: Array[Dictionary] = _in_category(category)
		if rows.is_empty() and not show_empty_categories:
			continue
		var section: VBoxContainer = _build_section(category, rows)
		section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.add_child(section)
		shown += rows.size()
	if shown == 0 and not show_empty_categories:
		add_child(_build_empty())


## Seconds remaining on the temporary bonuses, refreshed without rebuilding the
## list. The panel calls this while it is open.
func tick_timers() -> void:
	for label: Label in _timer_labels:
		var entry: Dictionary = _timer_labels[label]
		label.text = _format_remaining(UpgradeManager.get_temporary_remaining(
			(entry["data"] as UpgradeData).id, entry["weapon_id"]))


# Private

func _in_category(category: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		if (entry["data"] as UpgradeData).category == category:
			rows.push_back(entry)
	return rows


func _build_section(category: int, rows: Array[Dictionary]) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.name = "Category%d" % category
	section.add_theme_constant_override("separation", 6)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var glyph := MayhemIcon.new()
	glyph.kind = CATEGORY_ICONS[category]
	glyph.color = CATEGORY_COLORS[category]
	glyph.custom_minimum_size = Vector2(14, 14)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(glyph)
	var title := Label.new()
	title.theme_type_variation = &"HUDLabel"
	title.text = CATEGORY_TITLES[category]
	title.add_theme_color_override("font_color", CATEGORY_COLORS[category])
	header.add_child(title)
	section.add_child(header)

	if rows.is_empty():
		var none := Label.new()
		none.theme_type_variation = &"HUDLabel"
		none.text = "  -"
		none.add_theme_color_override("font_color", Tokens.DIM)
		section.add_child(none)
	for entry: Dictionary in rows:
		section.add_child(_build_row(entry))
	return section


func _build_row(entry: Dictionary) -> HBoxContainer:
	var data: UpgradeData = entry["data"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.tooltip_text = data.description

	var label := Label.new()
	label.theme_type_variation = &"HUDLabel"
	label.text = "  %s" % _row_text(entry)
	label.add_theme_color_override("font_color", Tokens.TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	if data.is_temporary:
		var timer := Label.new()
		timer.theme_type_variation = &"HUDLabel"
		timer.add_theme_color_override("font_color", Tokens.HAZARD)
		timer.text = _format_remaining(float(entry["remaining"]))
		row.add_child(timer)
		_timer_labels[timer] = entry
	return row


## "Magazine x2 (SMG)" - the weapon suffix only appears on WEAPON-category
## upgrades, which are the only ones scoped to a gun.
func _row_text(entry: Dictionary) -> String:
	var data: UpgradeData = entry["data"]
	var text: String = data.display_name.to_upper()
	var stacks: int = int(entry["stacks"])
	if stacks > 1:
		text += " x%d" % stacks
	var weapon_id: StringName = entry["weapon_id"]
	if weapon_id != &"":
		text += "  (%s)" % String(weapon_id).to_upper()
	return text


func _build_empty() -> Label:
	var label := Label.new()
	label.theme_type_variation = &"HUDLabel"
	label.text = EMPTY_TEXT
	label.add_theme_color_override("font_color", Tokens.DIM)
	return label


func _format_remaining(seconds: float) -> String:
	return "%0.0fs" % maxf(seconds, 0.0)
