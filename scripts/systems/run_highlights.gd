class_name RunHighlights
extends RefCounted
## Lo mejor de la run, en tres frases: la racha mas larga, la kill mas lejana,
## la oleada mas rapida contra su par.
##
## La pantalla de fin ya desarma la run en numeros (RunSummary), y los numeros
## sirven para la proxima run, no para contarla. Esto elige los momentos que vale
## la pena contar - lo que va arriba de la pantalla de fin y en la tarjeta para
## compartir (ShareCard) -, que tambien es lo que una pagina de itch o un
## trailer necesitan: "12 kills sin un rasguño" se entiende sin jugar.
##
## Cada candidato se pesa contra una referencia ("una buena run hace esto"), asi
## que el que sale primero es el mas notable para su propia escala y no el
## numero mas grande: 4 kills en un segundo y medio pesan mas que 30 m de tiro.
## Sin estado: lee RunRecord, o un diccionario con los mismos campos en los
## tests.

## Lo que una run buena logra en cada uno. El peso es valor / referencia.
const REF_BURST: float = 4.0
const REF_STREAK: float = 25.0
const REF_TOP_SPEED: float = 22.0
const REF_STYLE_BONUSES: float = 3.0
const REF_LONGEST_KILL: float = 30.0
## Terminar una oleada en el 75 % de su par ya es notable.
const REF_PAR_RATIO: float = 1.0 / 0.75
const REF_HEADSHOT_SHARE: float = 0.4
const REF_CLEAN_WAVES: float = 3.0
## Debajo de esto no es un momento, es ruido: "2 kills seguidas sin daño".
const MIN_WEIGHT: float = 0.35
## Con menos kills la proporcion de headshots no dice nada (ver RunRecord).
const MIN_KILLS_FOR_SHARE: int = 20
const DEFAULT_COUNT: int = 3


## Los `count` momentos de mas peso, de mayor a menor. Cada uno
## `{ "id", "title", "value", "detail", "weight" }`.
static func pick(record: Dictionary, count: int = DEFAULT_COUNT) -> Array[Dictionary]:
	var all: Array[Dictionary] = candidates(record)
	all.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["weight"]) > float(b["weight"]))
	if all.size() > count:
		all.resize(count)
	return all


## Lo que RunRecord sabe hoy, en el formato que lee `pick()`.
static func from_run_record() -> Dictionary:
	return {
		"best_burst": RunRecord.best_burst,
		"best_streak": RunRecord.best_streak,
		"top_speed": RunRecord.top_speed,
		"best_style_bonuses": RunRecord.best_style_bonuses,
		"best_style_total": RunRecord.best_style_total,
		"longest_kill": RunRecord.longest_kill,
		"kills": RunRecord.kills,
		"headshots": RunRecord.headshots,
		"flawless_waves": RunRecord.flawless_waves,
		"wave_log": RunRecord.wave_log,
	}


## Todos los que pasan el minimo, sin ordenar.
static func candidates(record: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var burst: int = int(record.get("best_burst", 0))
	if burst >= 2:
		_add(out, &"burst", "MULTIKILL", "%d kills" % burst,
			"in %.1f seconds" % RunRecord.BURST_WINDOW, burst / REF_BURST)
	var streak: int = int(record.get("best_streak", 0))
	_add(out, &"streak", "UNTOUCHED", "%d kills" % streak, "in a row without a scratch",
		streak / REF_STREAK)
	var speed: float = float(record.get("top_speed", 0.0))
	_add(out, &"top_speed", "TOP SPEED", "%.1f m/s" % speed, "the fastest you moved",
		speed / REF_TOP_SPEED)
	var bonuses: int = int(record.get("best_style_bonuses", 0))
	if bonuses >= 2:
		_add(out, &"style", "STYLE KILL", "%d bonuses" % bonuses,
			"on one kill (+%d)" % int(record.get("best_style_total", 0)),
			bonuses / REF_STYLE_BONUSES)
	var distance: float = float(record.get("longest_kill", 0.0))
	_add(out, &"longest_kill", "LONG SHOT", "%d m" % roundi(distance), "the farthest kill",
		distance / REF_LONGEST_KILL)
	var kills: int = int(record.get("kills", 0))
	if kills >= MIN_KILLS_FOR_SHARE:
		var share: float = float(record.get("headshots", 0)) / float(kills)
		_add(out, &"headshots", "HEADHUNTER", "%d%%" % roundi(share * 100.0),
			"of kills to the head", share / REF_HEADSHOT_SHARE)
	var clean: int = int(record.get("flawless_waves", 0))
	_add(out, &"clean_waves", "CLEAN", "%d waves" % clean, "without taking damage",
		clean / REF_CLEAN_WAVES)
	var fastest: Dictionary = fastest_wave(record.get("wave_log", []))
	if not fastest.is_empty():
		var ratio: float = float(fastest["ratio"])
		_add(out, &"fastest_wave", "SPEEDRUN", "Wave %d" % (int(fastest["wave"]) + 1),
			"%d%% under par" % roundi((1.0 - 1.0 / ratio) * 100.0) if ratio > 1.0
				else "on par", ratio / REF_PAR_RATIO)
	return out


## La oleada limpiada con mejor relacion par / duracion, o vacio. Solo las que
## traen `par` (RunRecord lo anota desde que existe esta pantalla).
static func fastest_wave(wave_log: Array) -> Dictionary:
	var best: Dictionary = {}
	for entry: Variant in wave_log:
		var wave: Dictionary = entry
		var par: float = float(wave.get("par", 0.0))
		var duration: float = float(wave.get("duration", 0.0))
		if not bool(wave.get("cleared", false)) or par <= 0.0 or duration <= 0.0:
			continue
		var ratio: float = par / duration
		if best.is_empty() or ratio > float(best["ratio"]):
			best = {"wave": int(wave.get("wave", 0)), "ratio": ratio}
	return best


## La frase de un momento, para el texto que se copia: "MULTIKILL 5 kills in 1.5
## seconds".
static func line(highlight: Dictionary) -> String:
	return "%s %s %s" % [highlight["title"], highlight["value"], highlight["detail"]]


static func _add(out: Array[Dictionary], id: StringName, title: String, value: String,
		detail: String, weight: float) -> void:
	if weight < MIN_WEIGHT:
		return
	out.append({"id": id, "title": title, "value": value, "detail": detail, "weight": weight})
