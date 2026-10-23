class_name UiMotion
extends RefCounted
## El movimiento de la interfaz, en un solo lugar: que un numero que cambio se
## hinche, que un panel llegue con inercia, que un "no" se sacuda.
##
## Utilidad estatica, como PhysicsLayers. Cada animacion va atada al nodo que
## anima (`create_tween()` sobre el), asi que muere con el; y la anterior del
## mismo tipo se mata antes de arrancar la nueva, porque dos tweens sobre la
## misma propiedad pelean y el ultimo frame lo gana cualquiera.
##
## Los tiempos salen de Tokens y ninguno pasa STATE_SETTLE_MAX.
##
## Una trampa de Godot que esto respeta: un Container le resetea escala y posicion
## a sus hijos cada vez que reacomoda. Hinchar un Label adentro de un HBox
## funciona mientras nada cambie de tamaño; si algo lo hace, la animacion salta
## a su estado final, que es justo el de reposo. Feo nunca, a lo sumo menos.

const _META_PREFIX: String = "ui_motion_"


## Un numero que cambio: se hincha y vuelve. `tint` lo tiñe un instante, y vuelve
## al color que el nodo ya tenia (modulate en blanco, el color del texto queda).
static func punch(control: Control, tint: Color = Color.WHITE,
		strength: float = Tokens.UI_PUNCH_SCALE) -> void:
	if not _ready_to_animate(control):
		return
	control.pivot_offset = control.size * 0.5
	var tween: Tween = _restart(control, &"punch")
	control.scale = Vector2.ONE * strength
	tween.tween_property(control, ^"scale", Vector2.ONE, Tokens.UI_PUNCH_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if tint != Color.WHITE and not reduce_flashing():
		control.modulate = Color(tint.r * 1.4, tint.g * 1.4, tint.b * 1.4, control.modulate.a)
		tween.parallel().tween_property(control, ^"modulate",
			Color(1.0, 1.0, 1.0, control.modulate.a), Tokens.UI_FLASH_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Un panel que llega: aparece desde `offset` mas abajo, con un poco de rebote.
## Solo para controles cuyo padre no es un Container (ver la nota de arriba).
static func enter(control: Control, offset: Vector2 = Vector2(0.0, Tokens.UI_ENTER_OFFSET),
		delay: float = 0.0) -> Tween:
	if not _ready_to_animate(control):
		return null
	var rest: Vector2 = _rest_position(control, &"enter")
	var tween: Tween = _restart(control, &"enter")
	control.position = rest + offset
	control.modulate.a = 0.0
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(control, ^"position", rest, Tokens.UI_ENTER_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(control, ^"modulate:a", 1.0, Tokens.UI_ENTER_TIME * 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return tween


## Aparece desde mas grande o mas chico que su tamaño. Para lo que vive adentro de
## un Container y no puede viajar: crece en su lugar.
static func pop_in(control: Control, from_scale: float, delay: float = 0.0,
		time: float = Tokens.UI_ENTER_TIME, target_alpha: float = 1.0) -> Tween:
	if not _ready_to_animate(control):
		return null
	control.pivot_offset = control.size * 0.5
	var tween: Tween = _restart(control, &"pop")
	control.scale = Vector2.ONE * from_scale
	control.modulate.a = 0.0
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(control, ^"scale", Vector2.ONE, time) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(control, ^"modulate:a", target_alpha, time * 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return tween


## Se va: se apaga y se encoge un poco. `then` corre al final (ocultar, liberar).
static func exit(control: Control, then: Callable = Callable()) -> Tween:
	if not _ready_to_animate(control):
		if then.is_valid():
			then.call()
		return null
	control.pivot_offset = control.size * 0.5
	# Misma llave que pop_in(): si el control vuelve a entrar mientras se iba, la
	# salida se cancela entera - incluido el `then`, que lo ocultaria recien llegado.
	var tween: Tween = _restart(control, &"pop")
	tween.tween_property(control, ^"modulate:a", 0.0, Tokens.UI_EXIT_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(control, ^"scale", Vector2.ONE * 0.96, Tokens.UI_EXIT_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if then.is_valid():
		tween.tween_callback(then)
	return tween


## "No": un sacudon horizontal que termina donde empezo. Es el idioma de un boton
## que no se puede apretar, sin texto que leer contra el reloj.
static func shake(control: Control) -> void:
	if not _ready_to_animate(control) or reduce_flashing():
		return
	var rest: Vector2 = _rest_position(control, &"shake")
	var tween: Tween = _restart(control, &"shake")
	var step: float = Tokens.UI_SHAKE_TIME / 5.0
	for amplitude: float in [1.0, -0.8, 0.55, -0.3]:
		tween.tween_property(control, ^"position:x", rest.x + Tokens.UI_SHAKE_PX * amplitude, step) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(control, ^"position:x", rest.x, step) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Si una animacion de este tipo esta en curso sobre el control.
static func is_running(control: Control, kind: StringName) -> bool:
	# has_meta() primero: get_meta() con default null no es un default para Godot,
	# y grita un error por la clave que falta.
	var key := StringName(_META_PREFIX + kind)
	if not control.has_meta(key):
		return false
	var tween: Variant = control.get_meta(key)
	return tween is Tween and (tween as Tween).is_running()


## Lo que pidio "reducir destellos" en opciones apaga los tintes, el brillo de las
## raras y el sacudon; el resto del movimiento queda, porque no destella.
static func reduce_flashing() -> bool:
	return bool(SettingsManager.get_value("accessibility/reduce_flashing"))


# Private

static func _ready_to_animate(control: Control) -> bool:
	return control != null and is_instance_valid(control) and control.is_inside_tree()


## Mata la animacion anterior de este tipo y arranca una nueva. Las de otro tipo
## siguen: un numero puede hincharse mientras su panel entra.
static func _restart(control: Control, kind: StringName) -> Tween:
	var key := StringName(_META_PREFIX + kind)
	if control.has_meta(key):
		var previous: Variant = control.get_meta(key)
		if previous is Tween and (previous as Tween).is_valid():
			(previous as Tween).kill()
	var tween: Tween = control.create_tween()
	control.set_meta(key, tween)
	return tween


## Donde descansa un control que se va a mover: donde esta ahora, salvo que una
## animacion del mismo tipo lo haya dejado a mitad de camino - ahi vale el reposo
## que se anoto al arrancarla. Se vuelve a medir cada vez porque un Container
## puede haberlo reubicado entre una animacion y la otra.
static func _rest_position(control: Control, kind: StringName) -> Vector2:
	var key := StringName(_META_PREFIX + "rest_" + kind)
	if not is_running(control, kind) or not control.has_meta(key):
		control.set_meta(key, control.position)
	return control.get_meta(key)
