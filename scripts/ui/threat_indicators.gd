class_name ThreatIndicators
extends Control
## Avisa del ataque que se esta preparando fuera de la pantalla: un chevron en el
## borde, del lado del enemigo, que se llena a medida que avanza su telegrafo.
##
## Los chevrons de DamageIndicators contestan "de donde me pegaron", y llegan
## tarde por definicion. Telegrafiar es obligatorio (CLAUDE.md 5.3), pero un
## telegrafo que pasa a espaldas del jugador solo se oye, y en una oleada de 40
## la preparacion de un Ranger atras se pierde entre todo lo demas: daño sin
## aviso visto. Esto lo trae al borde de la pantalla antes del golpe.
##
## Solo lo que esta fuera de cuadro: un enemigo a la vista ya muestra su propio
## brillo de preparacion, y duplicarlo en la HUD es ruido encima de la mira.
## Mismo color que el daño entrante (ENEMY) y la misma forma de chevron, pero
## hueco y en el borde, para que no se confunda con un golpe ya recibido.

const MAX_SHOWN: int = 6

var _camera: Camera3D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not bool(SettingsManager.get_value("hud/threat_indicators", true)):
		return
	var threats: Array[Dictionary] = collect_threats()
	var centre: Vector2 = size * 0.5
	for threat: Dictionary in threats:
		var angle: float = float(threat["angle"])
		var progress: float = float(threat["progress"])
		var direction := Vector2(sin(angle), -cos(angle))
		_chevron(centre + direction * Tokens.THREAT_CHEVRON_RADIUS, angle, progress)


# Public API

## Los ataques que se estan preparando fuera de cuadro, del mas avanzado al
## menos: `{ "angle": float, "progress": float, "enemy": Enemy }`. El angulo se
## mide como en DamageIndicators, 0 adelante y positivo a la derecha. Publico
## para los tests.
func collect_threats() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var camera: Camera3D = _get_camera()
	if camera == null:
		return result
	var eye: Vector3 = camera.global_position
	var max_range_sq: float = Tokens.THREAT_MAX_RANGE * Tokens.THREAT_MAX_RANGE
	for enemy: Enemy in CombatDirector.get_active_enemies():
		if not is_instance_valid(enemy) or not enemy.is_active or enemy.windup_progress <= 0.0:
			continue
		var at: Vector3 = enemy.global_position + Vector3.UP * Tokens.THREAT_AIM_HEIGHT
		if at.distance_squared_to(eye) > max_range_sq or is_on_screen(camera, at):
			continue
		var local: Vector3 = camera.global_transform.basis.inverse() * (at - eye)
		result.append({
			"angle": atan2(local.x, -local.z),
			"progress": enemy.windup_progress,
			"enemy": enemy,
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["progress"]) > float(b["progress"]))
	if result.size() > MAX_SHOWN:
		result.resize(MAX_SHOWN)
	return result


## En cuadro y no tapado por el borde: lo que el jugador ya puede ver. Con un
## margen hacia adentro, porque un enemigo pegado al borde de la pantalla se ve
## a medias y su brillo no alcanza.
static func is_on_screen(camera: Camera3D, world_position: Vector3) -> bool:
	if camera.is_position_behind(world_position):
		return false
	var viewport_size: Vector2 = camera.get_viewport().get_visible_rect().size
	var point: Vector2 = camera.unproject_position(world_position)
	var inset: Vector2 = viewport_size * Tokens.THREAT_SCREEN_INSET
	return Rect2(inset, viewport_size - inset * 2.0).has_point(point)


# Private

func _get_camera() -> Camera3D:
	if _camera != null and is_instance_valid(_camera):
		return _camera
	var player := Players.local() as Player
	if player == null:
		return null
	_camera = player.camera
	return _camera


## Hueco mientras se prepara, y se rellena desde la punta: lleno es "ahora".
func _chevron(tip: Vector2, angle: float, progress: float) -> void:
	var forward := Vector2(sin(angle), -cos(angle))
	var right := Vector2(forward.y, -forward.x)
	var half: float = Tokens.THREAT_CHEVRON_SIZE.x * 0.5
	var depth: float = Tokens.THREAT_CHEVRON_SIZE.y
	var outline := PackedVector2Array([
		tip,
		tip - forward * depth + right * half,
		tip - forward * depth - right * half,
		tip])
	var tint: Color = Tokens.ENEMY
	tint.a = lerpf(0.55, 1.0, progress)
	draw_polyline(outline, tint, Tokens.THREAT_CHEVRON_LINE, true)
	var fill: float = clampf(progress, 0.0, 1.0)
	if fill <= 0.0:
		return
	var fill_tint: Color = Tokens.ENEMY
	fill_tint.a = 0.85 * fill
	draw_colored_polygon(PackedVector2Array([
		tip,
		tip - forward * depth * fill + right * half * fill,
		tip - forward * depth * fill - right * half * fill]), fill_tint)
