extends Node
## La semilla de la run: de donde sale todo lo que se sortea en una partida.
##
## Antes cada sistema tenia su propio `RandomNumberGenerator` con `randomize()`
## -la tienda, las reglas, los regalos del publico, la dispersion del arma-, y no
## habia forma de volver a jugar la misma run: ni para un desafio entre amigos ni
## para reproducir un bug a partir de un log. Ahora cada uno pide su **corriente**
## por nombre, y todas salen de una sola semilla.
##
## Una corriente por sistema y no un generador compartido a proposito: si la
## tienda y los regalos sacaran del mismo, comprar una mejora mas cambiaria donde
## cae el proximo botiquin. Separadas, la tienda de la ola 4 es la misma aunque
## el jugador haya rerolleado distinto en la 3... salvo por la propia tienda.
##
## Lo que la semilla NO fija: la fisica, la IA (que decide por frame con jitter
## propio) ni el Host y la musica, que son cosmeticos. Dos runs con la misma
## semilla tienen las mismas ofertas, reglas, pedidos y regalos; no la misma
## pelea.

## Cuantos bits tiene una semilla. 40 entran justo en ocho caracteres de base 32,
## que es lo que se puede dictar o copiar a mano sin errores.
const SEED_BITS: int = 40
const MAX_SEED: int = (1 << SEED_BITS) - 1
## Base 32 de Crockford: sin I, L, O ni U, para que no haya dos caracteres que se
## confundan al copiarlos de una captura.
const ALPHABET: String = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const CODE_LENGTH: int = 8
const CODE_PREFIX: String = "MAYHEM"
## La parte del codigo que dice el modo cuando es ARSENAL. En ONE GUN va el id
## del arma.
const ARSENAL_TAG: String = "ARSENAL"

## La semilla de la run en curso. Siempre mayor que cero.
var run_seed: int = 1

## corriente -> RandomNumberGenerator
var _streams: Dictionary = {}


func _ready() -> void:
	begin()


# Public API

## Arranca una run. Con `fixed_seed` en cero sortea una nueva; con una semilla,
## la reusa - es lo que hace un codigo compartido.
func begin(fixed_seed: int = 0) -> void:
	run_seed = clampi(fixed_seed, 1, MAX_SEED) if fixed_seed > 0 else _fresh_seed()
	_streams.clear()


## La corriente `stream` de esta run. La misma instancia hasta el proximo
## `begin()`, asi que quien la guarda en una variable sigue sacando de ella.
func rng(stream: StringName) -> RandomNumberGenerator:
	var generator: RandomNumberGenerator = _streams.get(stream)
	if generator == null:
		generator = RandomNumberGenerator.new()
		generator.seed = hash("%d:%s" % [run_seed, stream])
		_streams[stream] = generator
	return generator


## La semilla de esta run en ocho caracteres, partidos en dos para leerlos.
func get_seed_text() -> String:
	return encode_seed(run_seed)


## El codigo para compartir: modo y semilla. `MAYHEM-ARSENAL-K7F2-QX9M` o
## `MAYHEM-SHOTGUN-K7F2-QX9M`.
static func make_code(seed_value: int, mode: int, weapon_id: StringName) -> String:
	var tag: String = ARSENAL_TAG
	if mode == GameManager.Mode.SINGLE_WEAPON and weapon_id != &"":
		tag = String(weapon_id).to_upper()
	return "%s-%s-%s" % [CODE_PREFIX, tag, encode_seed(seed_value)]


## Lee un codigo, completo o solo la semilla. Devuelve
## `{ "seed": int, "mode": int, "weapon_id": StringName }`, o vacio si no se
## entiende. Sin modo (solo la semilla), `mode` viene en -1: se juega con el que
## el jugador ya tenia elegido.
static func parse_code(text: String) -> Dictionary:
	var parts: PackedStringArray = text.strip_edges().to_upper().replace(" ", "").split("-", false)
	if parts.is_empty():
		return {}
	if parts[0] == CODE_PREFIX:
		parts.remove_at(0)
	var mode: int = -1
	var weapon_id: StringName = &""
	# La semilla son las dos ultimas partes (o una sola de ocho); lo que queda
	# adelante es el modo.
	var seed_text: String = ""
	if parts.size() >= 2 and parts[parts.size() - 1].length() + parts[parts.size() - 2].length() \
			== CODE_LENGTH:
		seed_text = parts[parts.size() - 2] + parts[parts.size() - 1]
		parts.resize(parts.size() - 2)
	elif parts[parts.size() - 1].length() == CODE_LENGTH:
		seed_text = parts[parts.size() - 1]
		parts.resize(parts.size() - 1)
	else:
		return {}
	var seed_value: int = decode_seed(seed_text)
	if seed_value <= 0:
		return {}
	if not parts.is_empty():
		# El id del arma puede llevar guion bajo pero nunca guion, asi que lo que
		# sobra es una sola parte.
		var tag: String = "-".join(parts)
		if tag == ARSENAL_TAG:
			mode = GameManager.Mode.ARSENAL
		else:
			mode = GameManager.Mode.SINGLE_WEAPON
			weapon_id = StringName(tag.to_lower())
	return {"seed": seed_value, "mode": mode, "weapon_id": weapon_id}


static func encode_seed(seed_value: int) -> String:
	var value: int = clampi(seed_value, 0, MAX_SEED)
	var chars: String = ""
	for _i: int in CODE_LENGTH:
		chars = ALPHABET[value & 31] + chars
		value >>= 5
	return "%s-%s" % [chars.substr(0, 4), chars.substr(4)]


## 0 si el texto no es una semilla. Perdona lo que Crockford perdona: O es 0,
## I y L son 1, y los guiones no cuentan.
static func decode_seed(text: String) -> int:
	var clean: String = text.strip_edges().to_upper().replace("-", "").replace(" ", "") \
		.replace("O", "0").replace("I", "1").replace("L", "1")
	if clean.length() != CODE_LENGTH:
		return 0
	var value: int = 0
	for character: String in clean:
		var digit: int = ALPHABET.find(character)
		if digit < 0:
			return 0
		value = (value << 5) | digit
	return value


# Private

func _fresh_seed() -> int:
	var generator := RandomNumberGenerator.new()
	generator.randomize()
	var value: int = ((generator.randi() << 8) | (generator.randi() & 0xFF)) & MAX_SEED
	return maxi(value, 1)
