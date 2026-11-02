class_name RunSummary
extends VBoxContainer
## El cuerpo de la pantalla de fin: el puntaje y de donde salio, y la run
## desarmada en tres columnas para leerla - como se peleo, oleada por oleada, y
## que hizo el daño.
##
## Antes era un parrafo de texto centrado: todos los numeros estaban, pero no se
## podian comparar. Una barra por oleada muestra en un vistazo cual fue la larga
## y la cara; una barra por enemigo, quien mato de verdad.
##
## Lee RunRecord en el momento de `show_run`: para entonces la run termino y
## nada mas lo cambia hasta el proximo reset.

const SHOP_CATALOG_PATH: String = "res://data/economy/shop_catalog.tres"
const ENEMY_DATA_PATH: String = "res://data/enemies/%s.tres"
## Cuantas filas por lista: mas de cinco es una tabla, no un resumen.
const TOP_ROWS: int = 5
const COLUMN_MIN_WIDTH: float = 380.0
const NAME_WIDTH: float = 130.0
const BAR_HEIGHT: float = 10.0

var _score_label: Label
var _best_badge: Label
## Lineas de mas que manda quien abre la pantalla (la maestria de las armas).
var _extra_lines: Array[String] = []


func _init() -> void:
	add_theme_constant_override(&"separation", Tokens.CLUSTER_GAP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## `info`: `victory`, `score`, `previous_best` (antes de anotar esta run),
## `breakdown` (`{kills, style, waves, bonus}`), `recap` (la linea de la muerte, si
## la hubo) y `lines` (Array[String], van abajo de todo). El resto sale de RunRecord.
func show_run(info: Dictionary) -> void:
	_extra_lines.assign(info.get("lines", []))
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	add_child(_build_score(info))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", Tokens.CLUSTER_GAP)
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(columns)
	columns.add_child(_build_combat())
	columns.add_child(_build_waves())
	columns.add_child(_build_threats(info))
	var extras: Control = _build_extras()
	if extras != null:
		add_child(extras)


## Cuenta el puntaje desde cero: el numero que mas importa entra ultimo y se ve
## llegar. Con reduce_flashing va directo.
func count_up() -> void:
	if _score_label == null:
		return
	var target: int = int(_score_label.get_meta(&"score", 0))
	if UiMotion.reduce_flashing() or not is_inside_tree():
		_score_label.text = str(target)
		return
	var tween: Tween = _score_label.create_tween()
	tween.tween_method(func(value: float) -> void: _score_label.text = str(roundi(value)),
		0.0, float(target), Tokens.RUN_END_COUNT_TIME) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	if _best_badge != null and _best_badge.visible:
		tween.tween_callback(UiMotion.punch.bind(_best_badge, Tokens.REWARD, 1.3))


# Bloques

func _build_score(info: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", Tokens.CLUSTER_GAP * 2)
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	var left := VBoxContainer.new()
	left.add_theme_constant_override(&"separation", 0)
	row.add_child(left)
	left.add_child(_caption("SCORE"))
	var score: int = int(info.get("score", 0))
	_score_label = Label.new()
	_score_label.name = "Score"
	_score_label.text = str(score)
	_score_label.set_meta(&"score", score)
	_score_label.add_theme_font_size_override(&"font_size", Tokens.SIZE_NUM_PRIMARY)
	left.add_child(_score_label)
	var previous_best: int = int(info.get("previous_best", 0))
	_best_badge = Label.new()
	_best_badge.name = "BestBadge"
	if score > previous_best and score > 0:
		_best_badge.text = "NEW BEST" if previous_best > 0 else "FIRST RUN ON THE BOARD"
		_best_badge.add_theme_color_override(&"font_color", Tokens.REWARD)
	else:
		_best_badge.text = "BEST %d  (%+d)" % [previous_best, score - previous_best]
		_best_badge.add_theme_color_override(&"font_color", Tokens.MUTED)
	_best_badge.add_theme_font_size_override(&"font_size", Tokens.SIZE_LABEL)
	left.add_child(_best_badge)

	# De donde salio el numero, como una sola barra partida: lo que el jugador
	# tiene que ver es que el estilo y las oleadas pesan.
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(560.0, 0.0)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_theme_constant_override(&"separation", 6)
	row.add_child(right)
	right.add_child(_caption("WHERE IT CAME FROM"))
	var breakdown: Dictionary = info.get("breakdown", {})
	var parts: Array = [
		["Kills", int(breakdown.get("kills", 0)), Tokens.TEXT],
		["Style", int(breakdown.get("style", 0)), Tokens.PLAYER],
		["Waves", int(breakdown.get("waves", 0)), Tokens.MUTED],
		["Victory", int(breakdown.get("bonus", 0)), Tokens.REWARD],
	]
	var bar := HBoxContainer.new()
	bar.name = "Breakdown"
	bar.add_theme_constant_override(&"separation", 2)
	bar.custom_minimum_size = Vector2(0.0, BAR_HEIGHT * 1.6)
	right.add_child(bar)
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override(&"separation", Tokens.CLUSTER_GAP)
	right.add_child(legend)
	for part: Array in parts:
		var amount: int = int(part[1])
		if amount <= 0:
			continue
		var piece := ColorRect.new()
		piece.color = part[2]
		piece.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		piece.size_flags_stretch_ratio = float(amount)
		piece.tooltip_text = "%s  %d" % [part[0], amount]
		bar.add_child(piece)
		var key := Label.new()
		key.text = "%s %d" % [String(part[0]).to_upper(), amount]
		key.add_theme_font_size_override(&"font_size", Tokens.SIZE_KEYBIND)
		key.add_theme_color_override(&"font_color", part[2])
		legend.add_child(key)
	if bar.get_child_count() == 0:
		bar.add_child(_track(1.0))
	return row


func _build_combat() -> Control:
	var body := GridContainer.new()
	body.columns = 2
	body.add_theme_constant_override(&"h_separation", Tokens.CLUSTER_GAP * 2)
	body.add_theme_constant_override(&"v_separation", 4)
	var kills: int = RunRecord.kills
	var headshot_rate: String = "-" if kills == 0 \
		else "%d%%" % roundi(100.0 * float(RunRecord.headshots) / float(kills))
	var rows: Array = [
		["Kills", str(kills)],
		["Headshot kills", headshot_rate],
		["Damage dealt", str(roundi(RunRecord.damage_done))],
		["Shots fired", str(RunRecord.shots_fired)],
		["Damage taken", str(roundi(RunRecord.damage_taken))],
		["Hits taken", str(RunRecord.hits_taken)],
		["Flawless waves", "%d / %d" % [RunRecord.flawless_waves, RunRecord.wave_log.size()]],
		["Money earned", str(RunRecord.earned)],
		["Purchases", str(RunRecord.purchases)],
		["Peak rating", _tier_name(RunRecord.peak_tier)],
	]
	for row: Array in rows:
		var name_label: Label = _caption(String(row[0]).to_upper())
		body.add_child(name_label)
		var value := Label.new()
		value.text = String(row[1])
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(value)
	return _column("COMBAT", body)


func _build_waves() -> Control:
	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 8)
	var chart := WaveChart.new()
	chart.name = "WaveChart"
	chart.set_entries(RunRecord.wave_log)
	body.add_child(chart)
	var key := Label.new()
	key.text = "HEIGHT = TIME   NUMBER = KILLS   COLOR = DAMAGE TAKEN"
	key.add_theme_font_size_override(&"font_size", Tokens.SIZE_KEYBIND)
	key.add_theme_color_override(&"font_color", Tokens.DIM)
	body.add_child(key)
	var highlights := Label.new()
	highlights.name = "Highlights"
	highlights.text = WaveChart.highlights(RunRecord.wave_log)
	highlights.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Con ancho fijo: un Label que parte lineas adentro de un Container sin
	# ancho pide, en el primer acomodo, una letra por renglon.
	highlights.custom_minimum_size = Vector2(COLUMN_MIN_WIDTH - 40.0, 0.0)
	highlights.add_theme_font_size_override(&"font_size", Tokens.SIZE_KEYBIND)
	highlights.add_theme_color_override(&"font_color", Tokens.MUTED)
	body.add_child(highlights)
	return _column("WAVES", body)


## Que te mato y quien hizo el daño; y del otro lado, a quien mataste.
func _build_threats(info: Dictionary) -> Control:
	var victory: bool = bool(info.get("victory", false))
	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 4)
	if not victory:
		var recap: Dictionary = RunRecord.get_death_recap()
		var killer := StringName(recap.get("killed_by", &""))
		if killer != &"":
			var headline := Label.new()
			headline.name = "KilledBy"
			headline.text = "KILLED BY %s" % DamageCause.label(killer).to_upper()
			headline.add_theme_color_override(&"font_color", Tokens.ENEMY)
			headline.add_theme_font_size_override(&"font_size", Tokens.SIZE_DISPLAY_SM)
			body.add_child(headline)
		var recap_text: String = String(info.get("recap", ""))
		if recap_text != "":
			var line: Label = _caption(recap_text)
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.custom_minimum_size = Vector2(COLUMN_MIN_WIDTH - 40.0, 0.0)
			body.add_child(line)
	body.add_child(_caption("DAMAGE TAKEN FROM"))
	_add_bars(body, RunRecord.damage_by_cause, "Nothing touched you")
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 6.0)
	body.add_child(spacer)
	body.add_child(_caption("KILLS BY ENEMY"))
	_add_bars(body, RunRecord.kills_by_type, "No kills")
	return _column("THREATS", body)


## Trofeos, maestria y kills por arma: lo que no entra en las columnas. Nulo si
## la run no dejo nada de eso.
func _build_extras() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	var trophies: Array[StringName] = RunRecord.get_trophies()
	if not trophies.is_empty():
		var flow := HFlowContainer.new()
		flow.name = "Trophies"
		flow.alignment = FlowContainer.ALIGNMENT_CENTER
		flow.add_theme_constant_override(&"h_separation", 8)
		for trophy: StringName in trophies:
			var chip := Label.new()
			chip.text = "  %s  " % RunRecord.get_label(trophy)
			chip.tooltip_text = RunRecord.get_description(trophy)
			chip.mouse_filter = Control.MOUSE_FILTER_PASS
			chip.add_theme_color_override(&"font_color", Tokens.REWARD)
			chip.add_theme_font_size_override(&"font_size", Tokens.SIZE_LABEL)
			var style := StyleBoxFlat.new()
			style.bg_color = Color(Tokens.REWARD, 0.12)
			style.border_color = Tokens.REWARD
			style.set_border_width_all(1)
			style.set_content_margin_all(4)
			chip.add_theme_stylebox_override(&"normal", style)
			flow.add_child(chip)
		box.add_child(flow)
	var lines: Array[String] = []
	var weapons: String = _weapon_kills_line()
	if weapons != "":
		lines.append(weapons)
	lines.append_array(_extra_lines)
	for line: String in lines:
		var label := Label.new()
		label.text = line
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override(&"font_size", Tokens.SIZE_LABEL)
		label.add_theme_color_override(&"font_color", Tokens.MUTED)
		box.add_child(label)
	if box.get_child_count() == 0:
		box.free()
		return null
	return box


# Piezas

func _column(title: String, body: Control) -> Control:
	var panel := PanelContainer.new()
	panel.name = title.capitalize()
	panel.theme_type_variation = &"HUDPanel"
	panel.custom_minimum_size = Vector2(COLUMN_MIN_WIDTH, 0.0)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, Tokens.CLUSTER_GAP)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	margin.add_child(box)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override(&"font_size", Tokens.SIZE_DISPLAY_SM)
	box.add_child(heading)
	box.add_child(body)
	return panel


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", Tokens.SIZE_LABEL)
	label.add_theme_color_override(&"font_color", Tokens.MUTED)
	return label


## Las `TOP_ROWS` entradas mas grandes de `counts` (id -> numero), una barra
## cada una en el color de quien es.
func _add_bars(parent: Control, counts: Dictionary, empty_text: String) -> void:
	var ids: Array = counts.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool:
		return float(counts[a]) > float(counts[b]))
	if ids.is_empty():
		var none: Label = _caption(empty_text)
		none.add_theme_color_override(&"font_color", Tokens.DIM)
		parent.add_child(none)
		return
	var top: float = float(counts[ids[0]])
	for id: Variant in ids.slice(0, TOP_ROWS):
		var amount: float = float(counts[id])
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		var name_label := Label.new()
		name_label.text = DamageCause.label(StringName(id))
		name_label.custom_minimum_size = Vector2(NAME_WIDTH, 0.0)
		name_label.clip_text = true
		name_label.add_theme_font_size_override(&"font_size", Tokens.SIZE_LABEL)
		row.add_child(name_label)
		var bar := HBoxContainer.new()
		bar.add_theme_constant_override(&"separation", 0)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.custom_minimum_size = Vector2(0.0, BAR_HEIGHT)
		var fill := ColorRect.new()
		fill.color = cause_color(StringName(id))
		fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fill.size_flags_stretch_ratio = amount
		bar.add_child(fill)
		if top > amount:
			bar.add_child(_track(top - amount))
		row.add_child(bar)
		var value := Label.new()
		value.text = str(roundi(amount))
		value.custom_minimum_size = Vector2(44.0, 0.0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_font_size_override(&"font_size", Tokens.SIZE_LABEL)
		row.add_child(value)
		parent.add_child(row)


func _track(ratio: float) -> ColorRect:
	var track := ColorRect.new()
	track.color = Tokens.RAISED
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.size_flags_stretch_ratio = ratio
	return track


## El color de un origen de daño o de un enemigo: el del cuerpo del enemigo, que
## es como el jugador lo reconoce en la arena.
static func cause_color(cause: StringName) -> Color:
	match cause:
		DamageCause.ARENA:
			return Tokens.HAZARD
		DamageCause.SELF:
			return Tokens.PLAYER
	var path: String = ENEMY_DATA_PATH % cause
	if ResourceLoader.exists(path):
		var data := load(path) as EnemyData
		if data != null:
			return data.body_color
	return Tokens.MUTED


func _tier_name(tier: int) -> String:
	var name_text: String = BroadcastRating.get_tier_name(tier)
	return name_text if name_text != "" else str(tier)


## "Shotgun 41 kills  -  Rifle 12 kills", de la que mas mato a la que menos.
func _weapon_kills_line() -> String:
	var counts: Dictionary = RunRecord.kills_by_weapon
	if counts.size() < 2:
		return ""
	var ids: Array = counts.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool:
		return int(counts[a]) > int(counts[b]))
	var catalog := load(SHOP_CATALOG_PATH) as ShopCatalog
	var parts: Array[String] = []
	for id: Variant in ids:
		var weapon: WeaponData = catalog.find_weapon(StringName(id)) if catalog != null else null
		var weapon_name: String = weapon.display_name if weapon != null else String(id).capitalize()
		parts.append("%s %d kills" % [weapon_name, int(counts[id])])
	return "  -  ".join(parts)
