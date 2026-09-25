class_name PayoutFeed
extends VBoxContainer
## Lo que la billetera acaba de hacer, bajo el contador de plata: cada kill con
## recargo y cada golpe que costo dinero.
##
## Se llama "payout" y no "bonus" a proposito: en esta HUD un bono ya es una
## mejora comprada (ver BonusPanel), y meter dos cosas distintas bajo la misma
## palabra es la clase de confusion que despues nadie desarma.
##
## Por que existe: sin esto el recargo por un 360 es un numero que sube un poco
## mas rapido en una esquina de la pantalla, que es indistinguible de no
## existir. El jugador tiene que poder leer **por que** le pagaron, o la proxima
## vez no lo intenta.
##
## Regla de ubicacion: cuelga del cluster de plata, fuera de la zona sin UI, y
## se arma y desarma solo - nunca reserva alto cuando esta vacio.

## Cuanto dura una fila antes de empezar a irse, y cuanto tarda en hacerlo.
const ROW_HOLD: float = 1.30
const ROW_FADE: float = 0.35
## Cuantas filas pueden convivir. Cuatro entra en una racha larga sin tapar los
## power-ups que van abajo; la quinta empuja a la mas vieja.
const MAX_ROWS: int = 4

## Filas vivas, de la mas vieja a la mas nueva.
var _rows: Array[Control] = []
var _font: FontFile
var _mono: FontFile


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override(&"separation", 4)
	_font = load(Tokens.FONT_UI_SEMI) as FontFile
	_mono = load(Tokens.FONT_MONO) as FontFile
	EventBus.kill_payout.connect(_on_kill_payout)
	EventBus.currency_lost.connect(_on_currency_lost)
	EventBus.wave_started.connect(_clear.unbind(2))


# Private

## Una kill sin recargo no dice nada que el contador no diga ya, asi que no
## escribe una fila: lo que este feed explica es por que cobraste **de mas**.
func _on_kill_payout(_reward: int, bonus_ids: Array, bonus_total: int,
		_position: Vector3) -> void:
	if bonus_ids.is_empty() or bonus_total <= 0:
		return
	var names: PackedStringArray = PackedStringArray()
	for id: StringName in bonus_ids:
		names.append(KillBonusTracker.get_label(id))
	_push_row(" · ".join(names), "+%d" % bonus_total, Tokens.REWARD)


func _on_currency_lost(amount: int, _reason: StringName) -> void:
	if amount <= 0:
		return
	_push_row("DAÑO", "-%d" % amount, Tokens.ENEMY)


func _push_row(text: String, amount: String, tint: Color) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override(&"separation", 10)

	var name_label := Label.new()
	name_label.text = text
	name_label.add_theme_color_override(&"font_color", tint)
	name_label.add_theme_font_size_override(&"font_size", Tokens.SIZE_LABEL)
	if _font != null:
		name_label.add_theme_font_override(&"font", _font)
	row.add_child(name_label)

	var amount_label := Label.new()
	amount_label.text = amount
	amount_label.add_theme_color_override(&"font_color", tint)
	amount_label.add_theme_font_size_override(&"font_size", Tokens.SIZE_NUM_SECOND)
	if _mono != null:
		amount_label.add_theme_font_override(&"font", _mono)
	row.add_child(amount_label)

	add_child(row)
	_rows.append(row)
	while _rows.size() > MAX_ROWS:
		_retire(_rows[0], 0.0)

	# Entra desde la derecha: el cluster esta pegado a ese borde, asi que la
	# fila se lee como algo que llega y no como algo que aparece.
	row.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(row, ^"modulate:a", 1.0, 0.08)
	tween.tween_interval(ROW_HOLD)
	tween.tween_callback(_retire.bind(row, ROW_FADE))


## Saca una fila. `fade` en cero la borra ya - es el caso de la fila que
## desplaza una racha larga, que no puede quedarse desvaneciendose mientras la
## nueva ya ocupo su lugar.
func _retire(row: Control, fade: float) -> void:
	if not is_instance_valid(row):
		return
	_rows.erase(row)
	if fade <= 0.0:
		row.queue_free()
		return
	var tween: Tween = create_tween()
	tween.tween_property(row, ^"modulate:a", 0.0, fade)
	tween.tween_callback(row.queue_free)


## Una oleada nueva empieza con el feed limpio: lo que cobraste en la anterior
## ya lo contó la pantalla de fin de oleada.
func _clear() -> void:
	for row: Control in _rows.duplicate():
		_retire(row, 0.0)
