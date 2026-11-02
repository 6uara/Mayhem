class_name WaveChart
extends Control
## Una barra por oleada de la run: la altura es lo que duro, el color cuanto
## daño entro. Es lo que la pantalla de fin tiene para contestar "donde se fue
## la run": una oleada larga y roja es la que hay que mirar.
##
## Las oleadas que no se llegaron a jugar quedan como un contorno, asi se ve
## cuanto faltaba. La oleada de la muerte va en el color del enemigo, rayada.
## Pasar el mouse por una barra da sus numeros.

## Donde el color de la barra llega al rojo entero: una oleada que costo media
## vida ya es una oleada mala.
const DAMAGE_FULL_RED: float = 50.0
const BAR_GAP: float = 6.0
const LABEL_HEIGHT: float = 18.0
const HATCH_STEP: float = 6.0

## `RunRecord.wave_log`.
var entries: Array[Dictionary] = []
var wave_count: int = WaveManager.WAVE_COUNT


func _init() -> void:
	custom_minimum_size = Vector2(0.0, 150.0)
	mouse_filter = Control.MOUSE_FILTER_PASS
	# Godot solo pide `_get_tooltip` si hay algun tooltip puesto.
	tooltip_text = " "


func set_entries(waves: Array[Dictionary], count: int = WaveManager.WAVE_COUNT) -> void:
	entries = waves
	wave_count = maxi(count, waves.size())
	queue_redraw()


## La oleada mas larga, la mas corta y la que mas daño costo, en una linea.
static func highlights(waves: Array[Dictionary]) -> String:
	var slowest: Dictionary = {}
	var fastest: Dictionary = {}
	var worst: Dictionary = {}
	for entry: Dictionary in waves:
		if not bool(entry.get("cleared", false)):
			continue
		if slowest.is_empty() or float(entry.duration) > float(slowest.duration):
			slowest = entry
		if fastest.is_empty() or float(entry.duration) < float(fastest.duration):
			fastest = entry
		if float(entry.damage) > 0.0 and (worst.is_empty()
				or float(entry.damage) > float(worst.damage)):
			worst = entry
	var parts: Array[String] = []
	if not fastest.is_empty():
		parts.append("FASTEST W%d %.1fs" % [int(fastest.wave) + 1, float(fastest.duration)])
	if not slowest.is_empty() and slowest != fastest:
		parts.append("SLOWEST W%d %.1fs" % [int(slowest.wave) + 1, float(slowest.duration)])
	if not worst.is_empty():
		parts.append("MOST HURT W%d (%d)" % [int(worst.wave) + 1, roundi(float(worst.damage))])
	return "   ".join(parts)


func _draw() -> void:
	if wave_count <= 0:
		return
	var font: Font = get_theme_default_font()
	var bar_w: float = (size.x - BAR_GAP * float(wave_count - 1)) / float(wave_count)
	var area_h: float = size.y - LABEL_HEIGHT
	var longest: float = 1.0
	for entry: Dictionary in entries:
		longest = maxf(longest, float(entry.duration))
	draw_line(Vector2(0.0, area_h), Vector2(size.x, area_h), Tokens.LINE, 1.0)

	for i: int in wave_count:
		var x: float = float(i) * (bar_w + BAR_GAP)
		var entry: Dictionary = _entry_for(i)
		if entry.is_empty():
			draw_rect(Rect2(x, area_h - 6.0, bar_w, 6.0), Tokens.LINE, false, 1.0)
		else:
			var h: float = maxf(4.0, area_h * float(entry.duration) / longest)
			var rect := Rect2(x, area_h - h, bar_w, h)
			if bool(entry.cleared):
				draw_rect(rect, bar_color(float(entry.damage)))
			else:
				_draw_hatched(rect, Tokens.ENEMY)
			var kills_text: String = str(int(entry.kills))
			draw_string(font, Vector2(x, area_h - h - 4.0), kills_text,
				HORIZONTAL_ALIGNMENT_CENTER, bar_w, Tokens.SIZE_KEYBIND, Tokens.MUTED)
		draw_string(font, Vector2(x, size.y - 2.0), str(i + 1),
			HORIZONTAL_ALIGNMENT_CENTER, bar_w, Tokens.SIZE_KEYBIND,
			Tokens.TEXT if not entry.is_empty() else Tokens.DIM)


## Cian si salio limpia, hacia el rojo del enemigo cuanto mas daño costo.
static func bar_color(damage: float) -> Color:
	if damage <= 0.0:
		return Tokens.PLAYER
	return Tokens.REWARD.lerp(Tokens.ENEMY, clampf(damage / DAMAGE_FULL_RED, 0.0, 1.0))


func _get_tooltip(at_position: Vector2) -> String:
	if wave_count <= 0:
		return ""
	var bar_w: float = (size.x - BAR_GAP * float(wave_count - 1)) / float(wave_count)
	var index: int = clampi(int(at_position.x / (bar_w + BAR_GAP)), 0, wave_count - 1)
	var entry: Dictionary = _entry_for(index)
	if entry.is_empty():
		return "Wave %d - not reached" % (index + 1)
	return "Wave %d%s\n%.1fs  -  %d kills  -  %d damage taken" % [index + 1,
		"" if bool(entry.cleared) else " (died here)", float(entry.duration),
		int(entry.kills), roundi(float(entry.damage))]


func _entry_for(wave: int) -> Dictionary:
	for entry: Dictionary in entries:
		if int(entry.wave) == wave:
			return entry
	return {}


func _draw_hatched(rect: Rect2, color: Color) -> void:
	draw_rect(rect, Color(color, 0.25))
	draw_rect(rect, color, false, 2.0)
	# Rayas a 45 grados desde el borde de abajo, recortadas a mano a los
	# costados: draw_line no recorta y la raya saldria del rect.
	var offset: float = -rect.size.y
	while offset < rect.size.x:
		var a := Vector2(rect.position.x + offset, rect.end.y)
		var b := a + Vector2(rect.size.y, -rect.size.y)
		if a.x < rect.position.x:
			a += Vector2(1.0, -1.0) * (rect.position.x - a.x)
		if b.x > rect.end.x:
			b -= Vector2(1.0, -1.0) * (b.x - rect.end.x)
		draw_line(a, b, color, 1.0)
		offset += HATCH_STEP
