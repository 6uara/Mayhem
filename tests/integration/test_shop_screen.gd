extends GutTest
## La tienda en dos pasos: comprar, despues armar la oleada que viene.
##
## Lo que se prueba es el recorrido -que el primer boton lleve al segundo paso
## solo cuando hay algo que elegir, que volver funcione y que el ultimo arranque
## la oleada-, las teclas que lo acortan contra el reloj, y que el reporte sume.

const SCENE: String = "res://scenes/ui/shop_screen.tscn"

var _screen: CanvasLayer
var _contract_chance: float = 0.0


func before_each() -> void:
	UpgradeManager.reset()
	EconomyManager.reset()
	BroadcastRules.reset()
	WaveManager.current_index = -1
	_contract_chance = BroadcastRules.pool.contract_chance
	_screen = add_child_autofree((load(SCENE) as PackedScene).instantiate())
	await wait_physics_frames(1)


func after_each() -> void:
	_screen.force_close()
	BroadcastRules.enabled = false
	BroadcastRules.pool.contract_chance = _contract_chance
	BroadcastRules.reset()
	UpgradeManager.reset()
	EconomyManager.reset()


func _open(breakdown: Dictionary = {}) -> void:
	_screen.open(breakdown, 2, 60.0)
	await wait_physics_frames(1)


func _offer_next_wave() -> void:
	BroadcastRules.enabled = true
	BroadcastRules.pool.contract_chance = 1.0
	BroadcastRules.prepare_offer(4, null)


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	_screen._input(event)


func _next_button() -> Button:
	return _screen.get_node("Root/Panel/VBox/ShopPage/Main/Footer/NextButton")


func test_without_an_offer_the_shop_button_starts_the_wave() -> void:
	await _open()
	watch_signals(_screen)
	assert_string_contains(_next_button().text, "START WAVE")
	_next_button().pressed.emit()
	assert_signal_emitted(_screen, "shop_closed", "no hay segundo paso que mostrar")


func test_with_an_offer_the_shop_leads_to_the_next_wave_page() -> void:
	_offer_next_wave()
	await _open()
	assert_eq(_screen.page, _screen.Page.SHOP, "arranca comprando")
	_next_button().pressed.emit()
	assert_eq(_screen.page, _screen.Page.NEXT_WAVE)
	assert_true(_screen.get_node("Root/Panel/VBox/NextPage").visible)
	assert_false(_screen.get_node("Root/Panel/VBox/ShopPage").visible,
		"cada paso se muestra solo")


func test_backspace_returns_to_the_shop_and_enter_starts_the_wave() -> void:
	_offer_next_wave()
	await _open()
	watch_signals(_screen)
	_key(KEY_ENTER)
	assert_eq(_screen.page, _screen.Page.NEXT_WAVE, "Enter en la tienda avanza")
	_key(KEY_BACKSPACE)
	assert_eq(_screen.page, _screen.Page.SHOP, "y se puede volver a comprar")
	_key(KEY_ENTER)
	_key(KEY_ENTER)
	assert_signal_emitted(_screen, "shop_closed", "Enter en el segundo paso arranca")


func test_the_number_keys_buy_the_card_they_name() -> void:
	EconomyManager.currency = 100000
	await _open()
	var first: Dictionary = _screen.shop.offers[0]
	_key(KEY_1)
	assert_false(_screen.shop.offers.has(first), "la tecla 1 compro la primera tarjeta")
	assert_lt(EconomyManager.currency, 100000)


func test_a_number_key_on_a_card_you_cannot_afford_does_nothing() -> void:
	EconomyManager.currency = 0
	await _open()
	var before: int = _screen.shop.offers.size()
	_key(KEY_1)
	assert_eq(_screen.shop.offers.size(), before)


func test_c_signs_and_unsigns_the_contract() -> void:
	_offer_next_wave()
	await _open()
	_screen.show_page(_screen.Page.NEXT_WAVE)
	_key(KEY_C)
	assert_true(BroadcastRules.is_contract_signed())
	_key(KEY_C)
	assert_false(BroadcastRules.is_contract_signed())


func test_the_number_keys_pick_the_rule_on_the_next_wave_page() -> void:
	_offer_next_wave()
	await _open()
	var rules: Array[BroadcastRule] = BroadcastRules.get_offered_rules()
	if rules.size() < 2:
		pass_test("la oferta trajo una sola regla: no hay nada que elegir")
		return
	_screen.show_page(_screen.Page.NEXT_WAVE)
	_key(KEY_2)
	assert_eq(BroadcastRules.get_chosen_rule(), rules[1])


func test_the_report_adds_up_and_subtracts_damage() -> void:
	await _open({"kills": 100, "completion_bonus": 50, "speed_bonus": 30,
		"no_damage_bonus": 0, "damage_loss": 20})
	var total: Label = _screen.get_node("Root/Panel/VBox/ShopPage/Side/Report/VBox/Total/Value")
	assert_eq(total.text, "+160")


func test_keys_do_nothing_while_the_pause_menu_is_up() -> void:
	_offer_next_wave()
	await _open()
	GameManager.is_paused = true
	_key(KEY_ENTER)
	GameManager.is_paused = false
	assert_eq(_screen.page, _screen.Page.SHOP)


# Movimiento

## La tienda congela el arbol, y con el arbol congelado los timers de GUT no
## corren: wait_seconds() esperaba hasta su propio tope de treinta segundos. La
## tienda anima igual (corre en PROCESS_MODE_ALWAYS), asi que para medir el
## reparto alcanza con soltar el congelamiento.
func _wait_for_the_deal() -> void:
	GameManager.set_freeze(GameManager.FREEZE_SHOP, false)
	await wait_seconds(Tokens.UI_STAGGER * 6.0 + Tokens.RARE_REVEAL_DELAY \
		+ Tokens.UI_ENTER_TIME + 0.15)


## Las cartas se reparten animadas, pero terminan donde tienen que estar: una que
## se puede pagar, entera; ninguna a medio camino.
func test_dealt_cards_settle_fully_visible() -> void:
	EconomyManager.currency = 100000
	await _open()
	await _wait_for_the_deal()
	var cards: Array[Node] = _screen.get_node("Root/Panel/VBox/ShopPage/Main/Cards").get_children()
	assert_false(cards.is_empty())
	for card: Node in cards:
		assert_almost_eq((card as Control).modulate.a, 1.0, 0.01)
		assert_almost_eq((card as Control).scale.x, 1.0, 0.01)


## Una que no alcanza llega apagada, no prendida y despues apagada.
func test_a_card_you_cannot_afford_is_dealt_dim() -> void:
	EconomyManager.currency = 0
	await _open()
	await _wait_for_the_deal()
	for card: Node in _screen.get_node("Root/Panel/VBox/ShopPage/Main/Cards").get_children():
		assert_lt((card as Control).modulate.a, 0.5)


## La rara se ve antes de leerse.
func test_a_rare_offer_gets_its_shine() -> void:
	await _open()
	var offers: Array[Dictionary] = [
		{"kind": Shop.Kind.UPGRADE, "id": &"test_rare", "name": "Rara", "description": "",
			"cost": 10, "category": 0, "owned": 0, "max_stacks": 1, "weapon_id": &"",
			"rare": true},
		{"kind": Shop.Kind.UPGRADE, "id": &"test_common", "name": "Comun", "description": "",
			"cost": 10, "category": 0, "owned": 0, "max_stacks": 1, "weapon_id": &""},
	]
	_screen._rebuild_cards(offers)
	var cards: Array[Node] = _screen.get_node("Root/Panel/VBox/ShopPage/Main/Cards").get_children() \
		.filter(func(node: Node) -> bool: return not node.is_queued_for_deletion())
	assert_true(cards[0].has_node(^"RareShine"), "la rara brilla")
	assert_false(cards[1].has_node(^"RareShine"), "la comun no")
