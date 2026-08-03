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
@onready var _skip_button: Button = $Root/Panel/VBox/SkipButton

var is_open: bool = false

var _time_left: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.visible = false
	_skip_button.pressed.connect(close)
	EventBus.currency_changed.connect(_on_currency_changed)
	if shop != null:
		shop.offers_changed.connect(_rebuild_cards)


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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	EventBus.shop_opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
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


func _rebuild_cards(offers: Array[Dictionary]) -> void:
	for child: Node in _cards.get_children():
		child.queue_free()
	for offer: Dictionary in offers:
		_cards.add_child(_make_card(offer))
	_refresh_affordability()


func _make_card(offer: Dictionary) -> Control:
	var card := VBoxContainer.new()
	card.custom_minimum_size = Vector2(CARD_MIN_WIDTH, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = String(offer["name"])
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(title)

	var tag := Label.new()
	tag.text = _category_label(offer)
	tag.modulate = Color(0.7, 0.75, 0.85)
	card.add_child(tag)

	var description := Label.new()
	description.text = String(offer["description"])
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(description)

	var button := Button.new()
	button.text = "Buy  %d" % int(offer["cost"])
	button.pressed.connect(_on_buy_pressed.bind(offer))
	button.set_meta(&"offer", offer)
	card.add_child(button)
	return card


func _category_label(offer: Dictionary) -> String:
	match int(offer["kind"]):
		Shop.Kind.WEAPON:
			return "WEAPON"
		Shop.Kind.UTILITY:
			return "UTILITY   carried %d/%d" % [int(offer["owned"]), int(offer["max_stacks"])]
	var names: Array[String] = ["MOBILITY", "WEAPON", "SURVIVABILITY"]
	var category: int = int(offer["category"])
	var suffix: String = ""
	if int(offer["max_stacks"]) > 1:
		suffix = "   owned %d/%d" % [int(offer["owned"]), int(offer["max_stacks"])]
	return "%s%s" % [names[category] if category >= 0 and category < 3 else "UPGRADE", suffix]


## Unaffordable cards are visibly dead rather than silently failing on click.
func _refresh_affordability() -> void:
	for card: Node in _cards.get_children():
		for child: Node in card.get_children():
			var button := child as Button
			if button == null or not button.has_meta(&"offer"):
				continue
			var offer: Dictionary = button.get_meta(&"offer")
			var affordable: bool = shop != null and shop.can_afford(offer)
			button.disabled = not affordable
			card.modulate = Color.WHITE if affordable else Color(1, 1, 1, 0.45)


func _on_buy_pressed(offer: Dictionary) -> void:
	if shop == null:
		return
	shop.buy(offer)
