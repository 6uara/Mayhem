class_name TutorialWaypoint
extends Control
## Una marca sobre lo que el paso del tutorial pide buscar: saber que tecla es no
## alcanza si no sabes adonde mirar, y un ancla en lo alto no se encuentra sola.
## Fuera de pantalla se pega al borde y apunta hacia el objetivo.
##
## Lleva el color de lo que marca (hoy las anclas, `WORLD_GRAPPLE`) y solo existe
## mientras dura el paso. Es de lo poco de la HUD que mira cada frame: la camara no
## avisa por señal cuando se mueve. Sin objetivo no procesa.

var target: Node3D:
	set(value):
		target = value
		visible = target != null
		set_process(target != null)
		queue_redraw()

var _font: Font
var _point: Vector2 = Vector2.ZERO
var _is_on_screen: bool = true
## Hacia donde apunta la flecha cuando el objetivo no esta en pantalla.
var _direction: Vector2 = Vector2.UP
var _distance: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = load(Tokens.FONT_MONO)
	target = target


func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or not is_instance_valid(target):
		return
	var world: Vector3 = target.global_position
	# La camara da coordenadas del viewport. Pasa por la proporcion de pantalla
	# porque la escala de la HUD (opciones) le cambia el tamaño a este control.
	var projected: Vector2 = camera.unproject_position(world) / get_viewport_rect().size * size
	var placed: Dictionary = place(projected, camera.is_position_behind(world), size,
		Tokens.WAYPOINT_MARGIN)
	_point = placed[&"point"]
	_is_on_screen = placed[&"on_screen"]
	_direction = placed[&"direction"]
	_distance = camera.global_position.distance_to(world)
	queue_redraw()


## Donde dibujar la marca. Detras de la camara la proyeccion sale espejada, asi que
## se invierte antes de pegarla al borde: si no, apuntaria para el lado contrario.
static func place(projected: Vector2, is_behind: bool, area: Vector2,
		margin: float) -> Dictionary:
	var center: Vector2 = area * 0.5
	var half: Vector2 = center - Vector2.ONE * margin
	var offset: Vector2 = projected - center
	if is_behind:
		offset = -offset if offset != Vector2.ZERO else Vector2.DOWN
	elif absf(offset.x) <= half.x and absf(offset.y) <= half.y:
		return {&"point": projected, &"on_screen": true, &"direction": Vector2.UP}
	var fit: float = minf(half.x / maxf(absf(offset.x), 0.001),
		half.y / maxf(absf(offset.y), 0.001))
	return {&"point": center + offset * fit, &"on_screen": false,
		&"direction": offset.normalized()}


func _draw() -> void:
	if target == null:
		return
	var tint: Color = Tokens.WORLD_GRAPPLE
	var reach: float = Tokens.WAYPOINT_SIZE
	if _is_on_screen:
		# Un rombo abierto: no tapa el ancla que esta marcando.
		draw_polyline(PackedVector2Array([
			_point + Vector2.UP * reach, _point + Vector2.RIGHT * reach,
			_point + Vector2.DOWN * reach, _point + Vector2.LEFT * reach,
			_point + Vector2.UP * reach]), tint, Tokens.WAYPOINT_STROKE)
	else:
		var side: Vector2 = _direction.orthogonal() * reach * 0.7
		draw_colored_polygon(PackedVector2Array([_point + _direction * reach,
			_point + side, _point - side]), tint)
	var width: float = Tokens.WAYPOINT_LABEL_W
	draw_string(_font, _point + Vector2(-width * 0.5, reach + Tokens.SIZE_KEYBIND + 4.0),
		"%d M" % roundi(_distance), HORIZONTAL_ALIGNMENT_CENTER, width, Tokens.SIZE_KEYBIND, tint)
