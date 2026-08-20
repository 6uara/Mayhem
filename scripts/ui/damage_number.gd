class_name DamageNumber
extends Node3D
## Pooled floating damage number over whatever a hit landed on. Cosmetic only -
## driven by EventBus.damage_dealt, the same signal HitstopController already
## consumes, so this never becomes a second source of truth for damage.
##
## No exact hit_position travels on that signal (only `target`), so this spawns
## near the target's own position rather than the precise impact point - close
## enough to read as attached to what got hit, without threading a new
## parameter through EventBus for it.
##
## Es cosmetico, y eso fija su presupuesto: un numero flotante no puede costar
## framerate. Medido con tools/profile_damage_numbers.gd, la primera version
## costaba mas de la mitad del framerate a 60 hits/s. Todo lo que sigue esta
## escrito contra esa medicion.

const LIFETIME: float = 0.7
const RISE_HEIGHT: float = 1.0
## Small per-number offset so simultaneous hits (a shotgun blast, several
## enemies dying in the same frame) don't stack into one unreadable column.
const JITTER_RADIUS: float = 0.18
const FADE_START_FRACTION: float = 0.35
## Un solo tamaño de fuente para todos los numeros, siempre.
##
## Antes habia dos, 48 para el cuerpo y 64 para la cabeza. Alternarlos obliga a
## Godot a rasterizar la fuente de nuevo a ese tamaño, y con headshots mezclados
## entre tiros normales eso pasaba varias veces por segundo.
##
## La distincion visual no se pierde: la escala del nodo hace que un headshot se
## siga viendo mas grande, y escalar un Node3D es una matriz, no una fuente nueva.
const FONT_SIZE: int = 48
## Cuanto mas grande se ve un headshot. Escala, no tamaño de fuente.
const HEADSHOT_SCALE: float = 1.35

@onready var _label: Label3D = $Label3D

var _timer: float = 0.0
var _is_playing: bool = false
## Altura desde la que sube este numero.
var _base_y: float = 0.0
## Daño acumulado que esta mostrando. Ver add_damage().
var _shown: float = 0.0


## `amount` is already the final applied damage (falloff, headshot multiplier,
## damage_taken_multiplier all resolved upstream) - this only ever displays it.
func play_at(hit_position: Vector3, amount: float, is_headshot: bool) -> void:
	var jitter := Vector3(
		randf_range(-JITTER_RADIUS, JITTER_RADIUS), 0.0,
		randf_range(-JITTER_RADIUS, JITTER_RADIUS))
	global_position = hit_position + jitter
	_base_y = global_position.y
	_shown = maxf(amount, 0.0)
	_label.text = "%d" % maxi(roundi(_shown), 0)
	_label.modulate = Color(Tokens.REWARD, 1.0) if is_headshot else Color(Tokens.TEXT, 1.0)
	scale = Vector3.ONE * (HEADSHOT_SCALE if is_headshot else 1.0)

	_timer = LIFETIME
	_is_playing = true


## Suma un golpe al numero que ya esta arriba de este objetivo en vez de pedir
## otro. Ver DamageNumberSpawner: es lo que evita que una escopeta pinte ocho
## Label3D en el mismo cuarto de segundo, y de paso se lee mejor - un 240 dice
## mas que ocho 30 amontonados.
func add_damage(amount: float, is_headshot: bool) -> void:
	if not _is_playing:
		return
	_shown += maxf(amount, 0.0)
	_label.text = "%d" % maxi(roundi(_shown), 0)
	if is_headshot:
		_label.modulate = Color(Tokens.REWARD, _label.modulate.a)
		scale = Vector3.ONE * HEADSHOT_SCALE
	# Un golpe nuevo le devuelve vida al numero, para que la suma se vea crecer
	# en vez de apagarse a mitad de camino.
	_timer = maxf(_timer, LIFETIME * 0.6)
	_label.modulate.a = 1.0


func is_playing() -> bool:
	return _is_playing


## Subida y desvanecido a mano, no con un Tween.
##
## Cada numero creaba el suyo con dos properties, y con fuego sostenido eso son
## decenas de Tweens por segundo instanciandose, registrandose en el arbol y
## muriendo - todo para animar dos valores que este _process, que ya corre para
## contar el tiempo de vida, calcula en dos lineas. La animacion es la misma; lo
## que se fue es la ceremonia.
func _process(delta: float) -> void:
	if not _is_playing:
		return
	_timer -= delta
	if _timer <= 0.0:
		ObjectPool.release(self)
		return

	var elapsed: float = 1.0 - (_timer / LIFETIME)
	# Ease out cubico: sale rapido del golpe y frena arriba.
	global_position.y = _base_y + RISE_HEIGHT * (1.0 - pow(1.0 - elapsed, 3.0))
	if elapsed > FADE_START_FRACTION:
		_label.modulate.a = 1.0 - ((elapsed - FADE_START_FRACTION) \
			/ (1.0 - FADE_START_FRACTION))


func _on_released() -> void:
	_is_playing = false
	_shown = 0.0
