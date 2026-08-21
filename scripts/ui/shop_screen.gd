extends CanvasLayer
## The between-wave shop, with the wave-complete breakdown above it.
##
## The breakdown shows all three income sources explicitly - kills, speed bonus,
## no-damage bonus - because that legibility is what makes the economy teachable
## (CLAUDE.md 5.5). The phase is skippable: banking the speed bonus is a real
## decision, so leaving early has to be one button.

signal shop_closed()

const CARD_MIN_WIDTH: int = 250

@export var shop: Shop
## Seconds the shop stays open before it closes itself.
@export var duration: float = 30.0  ## Tokens.SHOP_TIMER

@onready var _root: Control = $Root
@onready var _breakdown: Label = $Root/Panel/VBox/Breakdown
@onready var _currency: Label = $Root/Panel/VBox/Header/Currency
@onready var _timer_label: Label = $Root/Panel/VBox/Header/Timer
@onready var _cards: HBoxContainer = $Root/Panel/VBox/Cards
@onready var _reroll_button: Button = $Root/Panel/VBox/RerollRow/RerollButton
@onready var _skip_button: Button = $Root/Panel/VBox/SkipButton

var is_open: bool = false

var _time_left: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.visible = false
	_skip_button.pressed.connect(close)
	_reroll_button.pressed.connect(_on_reroll_pressed)
	EventBus.currency_changed.connect(_on_currency_changed)
	if shop != null:
		shop.offers_changed.connect(_rebuild_cards)
		shop.reroll_cost_changed.connect(_on_reroll_cost_changed)
		_reroll_button.visible = shop.catalog != null and shop.catalog.reroll_base_cost > 0


func _process(delta: float) -> void:
	if not is_open:
		return
	_time_left -= delta
	_timer_label.text = "%0.0fs" % maxf(_time_left, 0.0)
	if _time_left <= 0.0:
		close()


# Public API

## `breakdown` comes straight from EconomyManager.award_wave_bonuses().
func open(breakdown: Dictionary, wave_index: int, duration_seconds: float) -> void:
	if is_open:
		return
	is_open = true
	_time_left = duration
	_root.visible = true
	_breakdown.text = _format_breakdown(breakdown, wave_index, duration_seconds)
	_on_currency_changed(EconomyManager.currency)
	if shop != null:
		shop.roll_offers()
	# Por GameManager y no por get_tree() directo: el menu de pausa puede abrirse
	# encima de la tienda, y con los dos escribiendo el mismo booleano el que
	# cerraba ultimo descongelaba el juego abajo del otro.
	GameManager.set_freeze(GameManager.FREEZE_SHOP, true)
	EventBus.shop_opened.emit()


## The player is done shopping: back to the arena.
func close() -> void:
	force_close()


## Takes the screen down whatever state it is in - the player skipping out, or
## the run ending under it.
func force_close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	GameManager.set_freeze(GameManager.FREEZE_SHOP, false)
	EventBus.shop_closed.emit()
	shop_closed.emit()


# Private

func _format_breakdown(breakdown: Dictionary, wave_index: int, seconds: float) -> String:
	var speed: int = int(breakdown.get("speed_bonus", 0))
	var no_damage: int = int(breakdown.get("no_damage_bonus", 0))
	var lines: Array[String] = [
		"WAVE %d CLEAR   %0.1fs" % [wave_index + 1, seconds],
		"",
		"Kills            %d" % int(breakdown.get("kills", 0)),
		"Completion       %d" % int(breakdown.get("completion_bonus", 0)),
		"Speed bonus      %s" % ("%d" % speed if speed > 0 else "- (too slow)"),
		"No damage        %s" % ("%d" % no_damage if no_damage > 0 else "- (took damage)"),
	]
	return "\n".join(lines)


func _on_currency_changed(total: int) -> void:
	_currency.text = "%d" % total
	_refresh_affordability()


func _on_reroll_cost_changed(cost: int) -> void:
	_reroll_button.text = "Reroll  %d" % cost
	_refresh_affordability()


func _on_reroll_pressed() -> void:
	if shop == null:
		return
	shop.reroll()


func _rebuild_cards(offers: Array[Dictionary]) -> void:
	for child: Node in _cards.get_children():
		child.queue_free()
	for offer: Dictionary in offers:
		_cards.add_child(_make_card(offer))
	_refresh_affordability()


func _make_card(offer: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(CARD_MIN_WIDTH, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(&"panel", _card_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 18)
	margin.add_theme_constant_override(&"margin_top", 16)
	margin.add_theme_constant_override(&"margin_right", 18)
	margin.add_theme_constant_override(&"margin_bottom", 16)
	panel.add_child(margin)

	var card := VBoxContainer.new()
	card.add_theme_constant_override(&"separation", 8)
	margin.add_child(card)

	var tag := Label.new()
	tag.theme_type_variation = &"HUDLabel"
	tag.text = _category_label(offer)
	card.add_child(tag)

	var title := Label.new()
	title.text = String(offer["name"])
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override(&"font_size", 20)
	card.add_child(title)

	var description := Label.new()
	description.theme_type_variation = &"HUDLabel"
	description.text = String(offer["description"])
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	description.add_theme_color_override(&"font_color", Color(0.902, 0.91, 0.937, 0.85))
	card.add_child(description)

	var button := Button.new()
	button.text = "Buy  %d" % int(offer["cost"])
	button.pressed.connect(_on_buy_pressed.bind(offer))
	button.set_meta(&"offer", offer)
	card.add_child(button)
	return panel


## Flat dark chamfer panel, thin border - the affordable rail is added in
## `_refresh_affordability` so a card's own state (not a second stylebox) drives it.
func _card_style() -> StyleBox:
	var style := ChamferStyleBox.new()
	style.fill_color = Color(0.086, 0.098, 0.125, 1)
	style.fill_alpha = 0.85
	style.border_color = Color(0.173, 0.192, 0.251, 1)
	style.border_width = 1.0
	style.chamfer = 14.0
	style.rail_width = 3.0
	style.rail_color = Color(0.208, 0.878, 0.831, 1)
	style.rail_side = SIDE_LEFT
	return style


func _category_label(offer: Dictionary) -> String:
	match int(offer["kind"]):
		Shop.Kind.WEAPON:
			return "WEAPON"
		Shop.Kind.UTILITY:
			return "UTILITY   carried %d/%d" % [int(offer["owned"]), int(offer["max_stacks"])]
	var category: int = int(offer["category"])
	var suffix: String = ""
	if int(offer["max_stacks"]) > 1:
		suffix = "   owned %d/%d" % [int(offer["owned"]), int(offer["max_stacks"])]
	# WEAPON-category upgrades are scoped to whatever is equipped right now (see
	# Shop._build_pool) - name it, so the card never implies it follows the
	# player to whatever gets bought next.
	if category == UpgradeData.Category.WEAPON:
		var weapon_name: String = _weapon_name(StringName(offer.get("weapon_id", &"")))
		return "%s UPGRADE%s" % [weapon_name.to_upper(), suffix] if not weapon_name.is_empty() \
			else "WEAPON UPGRADE%s" % suffix
	var names: Array[String] = ["MOBILITY", "WEAPON", "SURVIVABILITY"]
	return "%s%s" % [names[category] if category >= 0 and category < 3 else "UPGRADE", suffix]


func _weapon_name(weapon_id: StringName) -> String:
	if weapon_id == &"" or shop == null or shop.catalog == null:
		return ""
	var data: WeaponData = shop.catalog.find_weapon(weapon_id)
	return data.display_name if data != null else ""


## Unaffordable cards are visibly dead rather than silently failing on click:
## the panel dims and its rail goes dark, the same "not current" language the
## rest of the UI uses for an inactive slot.
func _refresh_affordability() -> void:
	if shop != null and _reroll_button.visible:
		_reroll_button.disabled = not shop.can_reroll()
	for node: Node in _cards.get_children():
		var panel := node as Control
		var button: Button = _find_button(node)
		if panel == null or button == null or not button.has_meta(&"offer"):
			continue
		var offer: Dictionary = button.get_meta(&"offer")
		var affordable: bool = shop != null and shop.can_afford(offer)
		button.disabled = not affordable
		panel.modulate = Color.WHITE if affordable else Color(1, 1, 1, 0.45)
		var style: StyleBox = panel.get_theme_stylebox(&"panel")
		var chamfer_style := style as ChamferStyleBox
		if chamfer_style != null:
			chamfer_style.rail_color.a = 1.0 if affordable else 0.0


func _find_button(node: Node) -> Button:
	var button := node as Button
	if button != null:
		return button
	for child: Node in node.get_children():
		var found: Button = _find_button(child)
		if found != null:
			return found
	return null


func _on_buy_pressed(offer: Dictionary) -> void:
	if shop == null:
		return
	shop.buy(offer)
