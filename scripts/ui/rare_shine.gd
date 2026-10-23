class_name RareShine
extends Control
## El brillo de una tarjeta rara en la tienda: un halo ambar que respira alrededor
## del borde y un barrido de luz que la cruza de vez en cuando.
##
## Una rara no es "otra mejora": es una regla nueva para la run, y sale una por
## visita como mucho. La etiqueta RARE ya lo decia, pero con treinta segundos de
## reloj la tarjeta se leia igual que las otras hasta llegar a leerla. Esto hace
## que se vea antes de leerse.
##
## Ambar porque es REWARD: "esto paga" (09 Design Tokens and Color Law). Se dibuja
## a mano, con el mismo chaflan que ChamferStyleBox, para que el halo siga la
## silueta de la tarjeta y no un rectangulo.
##
## Con "reducir destellos" el halo queda quieto y el barrido no pasa.

## Cuanto se abre el halo por fuera del borde, en capas finas y juntas: con
## pocas capas separadas se leia como tres marcos y no como luz.
const GLOW_LAYERS: Array[float] = [1.0, 3.0, 5.0, 7.5, 10.5, 14.0]
const GLOW_ALPHA: Array[float] = [0.7, 0.42, 0.26, 0.15, 0.08, 0.04]
## Ancho de la franja del barrido, en proporcion al ancho de la tarjeta.
const SHEEN_WIDTH: float = 0.22
const SHEEN_ALPHA: float = 0.2

## El chaflan de la esquina de abajo a la derecha, el mismo que el de la tarjeta.
@export var chamfer: float = 14.0

var _time: float = 0.0
## Segundos hasta el proximo barrido. El primero sale apenas la carta termina de
## aterrizar en el reparto (ShopScreen._deal_cards()): antes seria invisible.
var _sheen_wait: float = Tokens.RARE_REVEAL_DELAY + Tokens.UI_ENTER_TIME
var _sheen_progress: float = -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Aditivo: luz que se suma a la tarjeta, no una franja de pintura encima del
	# texto. Con mezcla normal el barrido se veia como una banda marron.
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive


func _process(delta: float) -> void:
	_time += delta
	if not UiMotion.reduce_flashing():
		if _sheen_progress >= 0.0:
			_sheen_progress += delta / Tokens.RARE_SHEEN_TIME
			if _sheen_progress >= 1.0:
				_sheen_progress = -1.0
				_sheen_wait = Tokens.RARE_SHEEN_EVERY
		else:
			_sheen_wait -= delta
			if _sheen_wait <= 0.0:
				_sheen_progress = 0.0
	queue_redraw()


func _draw() -> void:
	var pulse: float = 0.5 + 0.5 * sin(_time * TAU / Tokens.RARE_GLOW_PERIOD)
	if UiMotion.reduce_flashing():
		pulse = 0.5
	var strength: float = lerpf(0.45, 1.0, pulse)
	for i: int in GLOW_LAYERS.size():
		var tint := Color(Tokens.REWARD, GLOW_ALPHA[i] * strength)
		var outline: PackedVector2Array = _outline(GLOW_LAYERS[i])
		outline.append(outline[0])
		draw_polyline(outline, tint, 3.0, true)
	if _sheen_progress >= 0.0:
		_draw_sheen(_sheen_progress)


## La franja diagonal, recortada a la silueta de la tarjeta para no pintar afuera.
func _draw_sheen(progress: float) -> void:
	var width: float = size.x * SHEEN_WIDTH
	var lean: float = size.y * 0.6
	var x: float = lerpf(-width - lean, size.x + width, ease(progress, 0.6))
	var band := PackedVector2Array([
		Vector2(x + lean, 0.0), Vector2(x + lean + width, 0.0),
		Vector2(x + width, size.y), Vector2(x, size.y)])
	# Sube y baja dentro del barrido: entra y sale suave en vez de cortarse.
	var alpha: float = SHEEN_ALPHA * sin(progress * PI)
	for piece: PackedVector2Array in Geometry2D.intersect_polygons(band, _outline(0.0)):
		draw_colored_polygon(piece, Color(Tokens.REWARD.lightened(0.5), alpha))


## El contorno de la tarjeta, abierto `grow` pixeles hacia afuera.
func _outline(grow: float) -> PackedVector2Array:
	var cut: float = chamfer + grow * 0.4
	return PackedVector2Array([
		Vector2(-grow, -grow),
		Vector2(size.x + grow, -grow),
		Vector2(size.x + grow, size.y + grow - cut),
		Vector2(size.x + grow - cut, size.y + grow),
		Vector2(-grow, size.y + grow),
	])
