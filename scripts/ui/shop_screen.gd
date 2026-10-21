extends CanvasLayer
## The between-wave shop, in two steps: buy, then set up the next wave.
##
## It was one column with everything stacked - the wave report, the offers, a
## reroll louder than the offers, the build, the house rule and the contract -
## and the teachers' playtest (2026-10-21) read it as noise. Now each page has
## one job. Step 1 is the shop: what you earned and what you own on the side,
## the offers in the middle. Step 2 is the next wave: pick the rule, sign the
## contract or not, start. With no offer from the Host there is no step 2 and
## the shop's button starts the wave directly.
##
## The report still shows every income source - kills, speed, no-damage - and
## now adds them up, because that legibility is what makes the economy
## teachable (CLAUDE.md 5.5). Leaving early is still one button away: banking
## the speed bonus is a real decision.

signal shop_closed()

## Lo que hace el reroll. Vive aca y no solo en la escena porque
## `_refresh_affordability()` lo reescribe con el motivo cuando no alcanza.
const REROLL_TOOLTIP: String = "New offers. Costs more each time this visit."
const CARD_MIN_WIDTH: int = 220
## Alto del icono en la cabecera de una tarjeta. Mas grande que en la HUD: aca
## hay tiempo para mirarlo y es lo primero que distingue una tarjeta de otra.
const CARD_ICON_BOX: float = 28.0
## Las teclas de compra: una por tarjeta, en el orden en que se ven. Contra un
## reloj de 30 segundos, apuntar el mouse a un boton es tiempo perdido.
const BUY_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5]
const STACK_PIP_SIZE := Vector2(18, 6)

enum Page { SHOP, NEXT_WAVE }

@export var shop: Shop
## Seconds the shop stays open before it closes itself.
@export var duration: float = 30.0  ## Tokens.SHOP_TIMER

@onready var _root: Control = $Root
@onready var _steps: Label = $Root/Panel/VBox/Header/Titles/Steps
@onready var _title: Label = $Root/Panel/VBox/Header/Titles/Title
@onready var _currency: Label = $Root/Panel/VBox/Header/Money/Currency
@onready var _timer_label: Label = $Root/Panel/VBox/Header/Clock/Timer
@onready var _shop_page: Control = $Root/Panel/VBox/ShopPage
@onready var _next_page: Control = $Root/Panel/VBox/NextPage
@onready var _report_title: Label = $Root/Panel/VBox/ShopPage/Side/Report/VBox/Title
@onready var _report_rows: GridContainer = $Root/Panel/VBox/ShopPage/Side/Report/VBox/Rows
@onready var _report_total: Label = $Root/Panel/VBox/ShopPage/Side/Report/VBox/Total/Value
@onready var _cards: HBoxContainer = $Root/Panel/VBox/ShopPage/Main/Cards
@onready var _reroll_button: Button = $Root/Panel/VBox/ShopPage/Main/RerollRow/RerollButton
@onready var _next_button: Button = $Root/Panel/VBox/ShopPage/Main/Footer/NextButton
@onready var _rule_title: Label = $Root/Panel/VBox/NextPage/RuleTitle
@onready var _rules: HBoxContainer = $Root/Panel/VBox/NextPage/Rules
@onready var _contract_title: Label = $Root/Panel/VBox/NextPage/ContractTitle
@onready var _contract_row: HBoxContainer = $Root/Panel/VBox/NextPage/Contract
@onready var _back_button: Button = $Root/Panel/VBox/NextPage/Footer/BackButton
@onready var _start_button: Button = $Root/Panel/VBox/NextPage/Footer/StartButton

var is_open: bool = false
var page: Page = Page.SHOP

var _time_left: float = 0.0
var _rule_group: ButtonGroup
var _contract_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.visible = false
	_next_button.pressed.connect(_on_next_pressed)
	_back_button.pressed.connect(show_page.bind(Page.SHOP))
	_start_button.pressed.connect(close)
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
	_timer_label.add_theme_color_override(&"font_color",
		Tokens.ENEMY if _time_left <= Tokens.SHOP_TIMER_URGENT else Tokens.TEXT)
	if _time_left <= 0.0:
		close()


## En `_input` y no en `_unhandled_input`: Enter es `ui_accept`, y con una tarjeta
## enfocada (pasa con solo hacerle clic) la GUI se lo comeria para volver a
## comprarla. Solo teclas de teclado: el boton A del joystick sigue apretando lo
## que tenga el foco, que es como se navega con joystick.
func _input(event: InputEvent) -> void:
	if not is_open or GameManager.is_paused:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if _handle_key(key.physical_keycode):
		get_viewport().set_input_as_handled()


# Public API

## `breakdown` comes straight from EconomyManager.award_wave_bonuses().
func open(breakdown: Dictionary, wave_index: int, duration_seconds: float) -> void:
	if is_open:
		return
	is_open = true
	_time_left = duration
	_root.visible = true
	_fill_report(breakdown, wave_index, duration_seconds)
	_on_currency_changed(EconomyManager.currency)
	_build_next_wave_page()
	show_page(Page.SHOP)
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


func show_page(target: Page) -> void:
	if target == Page.NEXT_WAVE and not _has_next_wave_page():
		target = Page.SHOP
	page = target
	_shop_page.visible = page == Page.SHOP
	_next_page.visible = page == Page.NEXT_WAVE
	_title.text = "ARMOURY" if page == Page.SHOP else "NEXT WAVE"
	var two_steps: bool = _has_next_wave_page()
	_steps.visible = two_steps
	_steps.text = "STEP %d OF 2" % (1 if page == Page.SHOP else 2)
	# Sin oferta del Host no hay segundo paso: el boton de la tienda arranca la
	# oleada, y lo dice.
	_next_button.text = "NEXT: HOUSE RULE  [ENTER]" if two_steps else "START WAVE  [ENTER]"
	_next_button.tooltip_text = "Done shopping. Pick the rule for the next wave." if two_steps \
		else _start_button.tooltip_text


# Private

## Una tecla de teclado sobre la pagina que se ve. Devuelve si la uso.
func _handle_key(code: Key) -> bool:
	if code == KEY_ENTER or code == KEY_KP_ENTER:
		if page == Page.SHOP:
			_on_next_pressed()
		else:
			close()
		return true
	if page == Page.NEXT_WAVE:
		if code == KEY_BACKSPACE:
			show_page(Page.SHOP)
			return true
		if code == KEY_C and _contract_button != null:
			_contract_button.button_pressed = not _contract_button.button_pressed
			return true
		var rule_index: int = BUY_KEYS.find(code)
		var rule_buttons: Array[Node] = _rules.get_children()
		if rule_index >= 0 and rule_index < rule_buttons.size():
			var button := _find_button(rule_buttons[rule_index])
			if button != null and not button.disabled:
				button.button_pressed = true
				button.pressed.emit()
			return true
		return false
	var index: int = BUY_KEYS.find(code)
	if index < 0:
		return false
	var cards: Array[Node] = _cards.get_children()
	if index < cards.size():
		var buy: Button = _find_button(cards[index])
		if buy != null and not buy.disabled:
			_on_buy_pressed(buy.get_meta(&"offer"))
	return true


func _on_next_pressed() -> void:
	if _has_next_wave_page():
		show_page(Page.NEXT_WAVE)
	else:
		close()


func _has_next_wave_page() -> bool:
	return BroadcastRules.has_offer()


# Report

## Una fila por ingreso, alineadas en columna, y el total abajo. Las filas de
## contrato, show y daño solo aparecen cuando movieron plata: una fila en cero de
## algo que no se jugo es ruido.
func _fill_report(breakdown: Dictionary, wave_index: int, seconds: float) -> void:
	_report_title.text = "WAVE %d CLEAR  -  %0.1fs" % [wave_index + 1, seconds]
	for child: Node in _report_rows.get_children():
		child.queue_free()
	var speed: int = int(breakdown.get("speed_bonus", 0))
	var no_damage: int = int(breakdown.get("no_damage_bonus", 0))
	var contract: int = int(breakdown.get("contract_bonus", 0))
	var show_money: int = int(breakdown.get("show_bonus", 0))
	var loss: int = int(breakdown.get("damage_loss", 0))
	var kills: int = int(breakdown.get("kills", 0))
	var completion: int = int(breakdown.get("completion_bonus", 0))
	_add_report_row("Kills", kills)
	_add_report_row("Wave clear", completion)
	_add_report_row("Speed bonus", speed, "too slow")
	_add_report_row("No damage", no_damage, "took damage")
	if contract > 0:
		_add_report_row("Contract", contract)
	if show_money > 0:
		_add_report_row("Show", show_money)
	if loss > 0:
		_add_report_row("Damage taken", -loss)
	var total: int = kills + completion + speed + no_damage + contract + show_money - loss
	_report_total.text = "%+d" % total


## `missed` es lo que se muestra en vez de un cero: dice por que no se cobro.
func _add_report_row(label_text: String, amount: int, missed: String = "") -> void:
	var label := Label.new()
	label.theme_type_variation = &"HUDLabel"
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_report_rows.add_child(label)
	var value := Label.new()
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if amount == 0 and not missed.is_empty():
		value.theme_type_variation = &"HUDLabel"
		value.text = missed
		value.add_theme_color_override(&"font_color", Tokens.DIM)
	else:
		value.text = "%d" % amount
		value.add_theme_color_override(&"font_color", Tokens.ENEMY if amount < 0 else Tokens.TEXT)
	_report_rows.add_child(value)


# Next wave

## Las reglas como tarjetas para elegir y el contrato como una tarjeta que se
## firma. El contrato era una linea con un switch chiquito a la derecha, y casi
## nadie lo veia.
func _build_next_wave_page() -> void:
	for child: Node in _rules.get_children() + _contract_row.get_children():
		child.queue_free()
	_contract_button = null
	if not _has_next_wave_page():
		return
	var rules: Array[BroadcastRule] = BroadcastRules.get_offered_rules()
	var wave_number: int = BroadcastRules.get_offer_wave() + 1
	_rule_title.visible = not rules.is_empty()
	_rule_title.text = "WAVE %d  -  %s" % [wave_number,
		"PICK THE HOUSE RULE  [1] [2]" if rules.size() > 1 else "THE HOUSE RULE"]
	_rule_group = ButtonGroup.new()
	for i: int in rules.size():
		_rules.add_child(_make_rule_card(rules[i], i, rules.size() > 1))
	_rules.visible = not rules.is_empty()

	var contract: BroadcastRule = BroadcastRules.get_offered_contract()
	_contract_title.visible = contract != null
	_contract_row.visible = contract != null
	if contract != null:
		_contract_row.add_child(_make_contract_card(contract))


func _make_rule_card(rule: BroadcastRule, index: int, can_choose: bool) -> Control:
	var button := Button.new()
	button.toggle_mode = true
	button.button_group = _rule_group
	button.text = "[%d]  %s\n%s" % [index + 1, rule.title, rule.description] if can_choose \
		else "%s\n%s" % [rule.title, rule.description]
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 120)
	button.tooltip_text = "This rule plays during the next wave."
	button.button_pressed = rule == BroadcastRules.get_chosen_rule()
	# Con una sola no hay nada que elegir: se muestra para que se sepa.
	button.disabled = not can_choose
	button.pressed.connect(BroadcastRules.choose_rule.bind(rule))
	return button


func _make_contract_card(contract: BroadcastRule) -> Control:
	var panel := _card_panel(Tokens.REWARD)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 24)
	panel.get_child(0).add_child(row)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.text = contract.title
	title.add_theme_font_size_override(&"font_size", 20)
	text.add_child(title)
	var description := Label.new()
	description.theme_type_variation = &"HUDLabel"
	description.text = contract.description
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(description)
	row.add_child(text)

	var payout := Label.new()
	payout.theme_type_variation = &"DisplaySmall"
	payout.text = "+%d" % contract.get_contract_payout(BroadcastRules.get_offer_wave())
	payout.tooltip_text = "Paid only if you clear the wave with the contract on."
	payout.mouse_filter = Control.MOUSE_FILTER_PASS
	payout.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(payout)

	_contract_button = Button.new()
	_contract_button.toggle_mode = true
	_contract_button.custom_minimum_size = Vector2(220, 52)
	_contract_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_contract_button.tooltip_text = "Optional. Signed, the handicap plays next wave and pays if you clear it."
	_contract_button.set_pressed_no_signal(BroadcastRules.is_contract_signed())
	_contract_button.toggled.connect(_on_contract_toggled)
	_on_contract_toggled(_contract_button.button_pressed)
	row.add_child(_contract_button)
	return panel


func _on_contract_toggled(signed: bool) -> void:
	BroadcastRules.set_contract_signed(signed)
	if _contract_button != null:
		_contract_button.text = "SIGNED  [C]" if signed else "SIGN  [C]"


# Offers

func _on_currency_changed(total: int) -> void:
	_currency.text = "%d" % total
	_refresh_affordability()


func _on_reroll_cost_changed(cost: int) -> void:
	_reroll_button.text = "[R]  REROLL   %d" % cost
	_refresh_affordability()


func _on_reroll_pressed() -> void:
	if shop == null:
		return
	shop.reroll()


func _rebuild_cards(offers: Array[Dictionary]) -> void:
	for child: Node in _cards.get_children():
		child.queue_free()
	for i: int in offers.size():
		_cards.add_child(_make_card(offers[i], i))
	_refresh_affordability()


func _make_card(offer: Dictionary, index: int) -> Control:
	var accent: Color = _offer_color(offer)
	var panel := _card_panel(accent)
	panel.custom_minimum_size = Vector2(CARD_MIN_WIDTH, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var card := VBoxContainer.new()
	card.add_theme_constant_override(&"separation", 10)
	panel.get_child(0).add_child(card)

	# Tecla, icono y categoria en la misma fila: el icono dice **que** es de un
	# vistazo y la etiqueta de que categoria, que son las dos preguntas que se
	# hacen antes de leer el nombre.
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 10)
	if index < BUY_KEYS.size():
		var key := Label.new()
		key.theme_type_variation = &"Keybind"
		key.text = "[%d]" % (index + 1)
		key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		header.add_child(key)
	var glyph: Control = _card_icon(offer)
	if glyph != null:
		header.add_child(glyph)
	var tag := Label.new()
	tag.theme_type_variation = &"HUDLabel"
	tag.text = _category_label(offer)
	tag.add_theme_color_override(&"font_color", accent)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(tag)
	card.add_child(header)

	# Una rara se anuncia: no es "otra mejora", es una regla nueva para la run.
	if bool(offer.get("rare", false)):
		var rare := Label.new()
		rare.theme_type_variation = &"HUDLabel"
		rare.text = "RARE  -  NEW RULE"
		rare.add_theme_color_override(&"font_color", Tokens.REWARD)
		card.add_child(rare)

	var title := Label.new()
	title.text = String(offer["name"])
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override(&"font_size", 22)
	card.add_child(title)

	var description := Label.new()
	description.theme_type_variation = &"HUDLabel"
	description.text = String(offer["description"])
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	description.add_theme_color_override(&"font_color", Color(Tokens.TEXT, 0.85))
	card.add_child(description)

	# Los stacks como pips: "owned 1/3" habia que leerlo, tres rayitas con una
	# llena se ven.
	var max_stacks: int = int(offer.get("max_stacks", 1))
	if max_stacks > 1:
		var pips := SegmentStrip.new()
		pips.segment_size = STACK_PIP_SIZE
		pips.gap = 4.0
		pips.filled_color = accent
		pips.empty_color = Tokens.DIM
		pips.configure(max_stacks, int(offer.get("owned", 0)))
		pips.tooltip_text = "Owned %d of %d." % [int(offer.get("owned", 0)), max_stacks]
		card.add_child(pips)

	# El precio grande y aparte del boton: es el numero que se compara contra la
	# plata de arriba, y adentro del boton se perdia.
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override(&"separation", 12)
	var price := Label.new()
	price.theme_type_variation = &"DisplaySmall"
	price.text = "%d" % int(offer["cost"])
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(price)
	var button := Button.new()
	button.text = "BUY"
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 44)
	button.pressed.connect(_on_buy_pressed.bind(offer))
	button.set_meta(&"offer", offer)
	bottom.add_child(button)
	card.add_child(bottom)
	return panel


## Panel de tarjeta con su margen ya puesto: el contenido va en `get_child(0)`.
func _card_panel(accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", _card_style(accent))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 20)
	margin.add_theme_constant_override(&"margin_top", 16)
	margin.add_theme_constant_override(&"margin_right", 18)
	margin.add_theme_constant_override(&"margin_bottom", 16)
	panel.add_child(margin)
	return panel


## El icono de una oferta, o null si no hay ninguno para ella.
##
## Una mejora lo busca por convencion (`IconSet.upgrade(id)`, mismo id que el
## `.tres`); un arma usa la geometria que `MayhemIcon` ya dibuja, que espeja el
## viewmodel y por lo tanto enseña la silueta del arma antes de comprarla.
func _card_icon(offer: Dictionary) -> Control:
	var id := StringName(offer.get("id", &""))
	if int(offer["kind"]) == Shop.Kind.WEAPON:
		var weapon_icon := MayhemIcon.new()
		weapon_icon.kind = _weapon_icon_kind(id)
		weapon_icon.color = Tokens.TEXT
		weapon_icon.custom_minimum_size = Vector2(CARD_ICON_BOX, CARD_ICON_BOX)
		weapon_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return weapon_icon if weapon_icon.kind != MayhemIcon.Kind.NONE else null
	if not IconSet.has(IconSet.UPGRADE, id):
		return null
	return IconSet.make(IconSet.UPGRADE, id, _offer_color(offer), CARD_ICON_BOX)


func _weapon_icon_kind(weapon_id: StringName) -> MayhemIcon.Kind:
	match weapon_id:
		&"rifle_ak", &"rifle": return MayhemIcon.Kind.RIFLE
		&"shotgun": return MayhemIcon.Kind.SHOTGUN
		&"smg": return MayhemIcon.Kind.SMG
		&"pistol": return MayhemIcon.Kind.PISTOL
	return MayhemIcon.Kind.NONE


## El color de la categoria, de Tokens y no de una copia local - ver
## bonus_list.gd, que tenia la suya y no coincidia. Un arma no tiene categoria y
## va en el color del texto: es un cambio de equipo, no una mejora.
func _offer_color(offer: Dictionary) -> Color:
	match int(offer.get("category", -1)):
		UpgradeData.Category.MOBILITY: return Tokens.CATEGORY_COLOR["mobility"]
		UpgradeData.Category.WEAPON: return Tokens.CATEGORY_COLOR["weapon"]
		UpgradeData.Category.SURVIVABILITY: return Tokens.CATEGORY_COLOR["survivability"]
	return Tokens.TEXT


## Flat dark chamfer panel, thin border, the rail in the card's own accent.
## `_refresh_affordability` darkens the rail when the card can't be bought.
func _card_style(accent: Color) -> StyleBox:
	var style := ChamferStyleBox.new()
	style.fill_color = Tokens.RAISED
	style.fill_alpha = 0.85
	style.border_color = Tokens.LINE
	style.border_width = 1.0
	style.chamfer = 14.0
	style.rail_width = 4.0
	style.rail_color = accent
	style.rail_side = SIDE_LEFT
	return style


func _category_label(offer: Dictionary) -> String:
	if int(offer["kind"]) == Shop.Kind.WEAPON:
		var current: String = _equipped_weapon_name()
		return "NEW WEAPON  -  REPLACES %s" % current.to_upper() if not current.is_empty() \
			else "NEW WEAPON"
	var category: int = int(offer["category"])
	# WEAPON-category upgrades are scoped to whatever is equipped right now (see
	# Shop._build_pool) - name it, so the card never implies it follows the
	# player to whatever gets bought next.
	if category == UpgradeData.Category.WEAPON:
		var weapon_name: String = _weapon_name(StringName(offer.get("weapon_id", &"")))
		return "%s UPGRADE" % weapon_name.to_upper() if not weapon_name.is_empty() \
			else "WEAPON UPGRADE"
	var names: Array[String] = ["MOBILITY", "WEAPON", "SURVIVABILITY"]
	return names[category] if category >= 0 and category < 3 else "UPGRADE"


func _weapon_name(weapon_id: StringName) -> String:
	if weapon_id == &"" or shop == null or shop.catalog == null:
		return ""
	var data: WeaponData = shop.catalog.find_weapon(weapon_id)
	return data.display_name if data != null else ""


func _equipped_weapon_name() -> String:
	var player := Players.local() as Player
	if player == null or player.weapon == null or player.weapon.data == null:
		return ""
	return player.weapon.data.display_name


## Unaffordable cards are visibly dead rather than silently failing on click:
## the panel dims and its rail goes dark, the same "not current" language the
## rest of the UI uses for an inactive slot.
func _refresh_affordability() -> void:
	if shop != null and _reroll_button.visible:
		_reroll_button.disabled = not shop.can_reroll()
		# Un boton apagado sin decir por que se lee como un bug; el tooltip de
		# la escena explica que hace, este agrega por que no se puede.
		_reroll_button.tooltip_text = REROLL_TOOLTIP if not _reroll_button.disabled \
			else "%s\n%s" % [REROLL_TOOLTIP, _short_text(shop.get_reroll_cost())]
	for node: Node in _cards.get_children():
		var panel := node as Control
		var button: Button = _find_button(node)
		if panel == null or button == null or not button.has_meta(&"offer"):
			continue
		var offer: Dictionary = button.get_meta(&"offer")
		var affordable: bool = shop != null and shop.can_afford(offer)
		button.disabled = not affordable
		button.tooltip_text = "" if affordable else _short_text(int(offer["cost"]))
		panel.modulate = Color.WHITE if affordable else Color(1, 1, 1, 0.45)
		var chamfer_style := panel.get_theme_stylebox(&"panel") as ChamferStyleBox
		if chamfer_style != null:
			chamfer_style.rail_color.a = 1.0 if affordable else 0.0


## Cuanto falta, en la moneda que la HUD muestra.
func _short_text(cost: int) -> String:
	return "Not enough money: %d short." % maxi(cost - EconomyManager.currency, 0)


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
