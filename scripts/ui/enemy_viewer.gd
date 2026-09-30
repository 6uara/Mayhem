extends Node3D
## Visor de enemigos: cada arquetipo parado solo sobre un piso, con camara
## orbital y botones para disparar sus estados.
##
## Existe para juzgar modelos y animaciones sin jugar una oleada: un modelo nuevo
## se mira de cerca, girandolo, caminando y usando su habilidad, y eso en partida
## pasa a veinte metros y en medio segundo.
##
## Usa el `Enemy` de verdad con su `EnemyData` de verdad - la misma presentacion,
## el mismo gait, el mismo `EnemyModelMotion` que en partida - pero con la IA y
## la fisica apagadas. El visor mueve el cuerpo a mano (caminar en circulo) y le
## escribe `velocity`, que es lo unico que lee la animacion. Asi lo que se ve
## aca es exactamente lo que se ve jugando, sin que el bicho salga corriendo.
##
## Se abre desde el menu principal (solo en builds de debug) o con `viewer` en la
## consola de desarrollo. Tambien corre suelto con F6 en el editor.

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const THEME: Theme = preload("res://ui/mayhem_theme.tres")
const DATA_DIR: String = "res://data/enemies"

const WALK_RADIUS: float = 3.5
const ZOOM_MIN: float = 1.5
const ZOOM_MAX: float = 18.0
const ORBIT_SENSITIVITY: float = 0.3
const TURNTABLE_DEGREES_PER_SECOND: float = 25.0

const HITBOX_COLOR := Color(1.0, 0.23, 0.33, 0.28)
const HEAD_COLOR := Color(1.0, 0.69, 0.13, 0.4)
const BODY_COLOR := Color(0.21, 0.88, 0.83, 0.18)

const GRID_SHADER: String = """
shader_type spatial;
render_mode unshaded;
uniform vec4 base_color : source_color = vec4(0.06, 0.07, 0.09, 1.0);
uniform vec4 line_color : source_color = vec4(0.21, 0.88, 0.83, 0.35);
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 cell = abs(fract(world_pos.xz - 0.5) - 0.5) / fwidth(world_pos.xz);
	float line = 1.0 - clamp(min(cell.x, cell.y), 0.0, 1.0);
	vec2 axis = abs(world_pos.xz) / fwidth(world_pos.xz);
	float axes = 1.0 - clamp(min(axis.x, axis.y), 0.0, 1.0);
	ALBEDO = mix(base_color.rgb, line_color.rgb, max(line * line_color.a, axes));
}
"""

var _archetypes: Array[EnemyData] = []
var _enemy: Enemy
var _data: EnemyData
var _camera: Camera3D

var _yaw: float = 35.0
var _pitch: float = -18.0
var _distance: float = 6.0
var _dragging: bool = false

var _walking: bool = false
var _speed_scale: float = 1.0
var _walk_angle: float = 0.0
var _turntable: bool = true
var _show_hitboxes: bool = false

var _info: Label
var _archetype_list: VBoxContainer
var _clip_list: VBoxContainer
var _fuse_toggle: CheckButton
var _walk_toggle: CheckButton
var _hitbox_meshes: Dictionary = {}  # CollisionShape3D -> MeshInstance3D
var _windup_tween: Tween


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_world()
	_build_ui()
	_archetypes = _load_archetypes()
	for data: EnemyData in _archetypes:
		var button := Button.new()
		button.text = data.display_name.to_upper()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_show_archetype.bind(data))
		_archetype_list.add_child(button)
	if not _archetypes.is_empty():
		_show_archetype(_archetypes[0])


func _process(delta: float) -> void:
	if _enemy == null or _data == null:
		return
	_tick_body(delta)
	_tick_camera()
	if _show_hitboxes:
		_sync_hitboxes()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()
		return
	var button := event as InputEventMouseButton
	if button != null:
		match button.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_dragging = button.pressed
			MOUSE_BUTTON_WHEEL_UP:
				_distance = maxf(_distance * 0.9, ZOOM_MIN)
			MOUSE_BUTTON_WHEEL_DOWN:
				_distance = minf(_distance * 1.1, ZOOM_MAX)
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		_yaw -= motion.relative.x * ORBIT_SENSITIVITY
		_pitch = clampf(_pitch - motion.relative.y * ORBIT_SENSITIVITY, -80.0, 20.0)


# Archetype

func _show_archetype(data: EnemyData) -> void:
	_data = data
	if _enemy == null:
		_enemy = ENEMY_SCENE.instantiate() as Enemy
		add_child(_enemy)
	# El mismo camino que un cuerpo que sale del pool: setup() reconstruye modelo,
	# gait, animacion, hitboxes y marcadores para el arquetipo nuevo.
	_enemy.setup(data, Vector3.ZERO)
	_freeze_ai()
	_walk_angle = 0.0
	_enemy.global_position = _rest_position()
	_enemy.rotation = Vector3.ZERO
	_enemy.velocity = Vector3.ZERO
	_distance = clampf(maxf(data.collision_height, 1.0) * 3.2, ZOOM_MIN, ZOOM_MAX)
	_fuse_toggle.button_pressed = false
	_fuse_toggle.visible = data.has_fuse
	_clear_hitbox_meshes()
	_rebuild_clip_list()
	_refresh_info()


## La IA y la fisica fuera: el visor mueve el cuerpo a mano. Sin esto el bicho
## busca al jugador, se cae por gravedad o, si es una bomba, se arma y revienta.
func _freeze_ai() -> void:
	_enemy.set_physics_process(false)
	_enemy._clear_behavior_tree()
	CombatDirector.unregister(_enemy)
	if _enemy.health != null:
		_enemy.health.is_invulnerable = true


## Los voladores se muestran a su altura de crucero; los demas, en el piso.
func _rest_position() -> Vector3:
	var height: float = _data.flight_height if _data.can_fly else 0.0
	return Vector3(0.0, height, 0.0)


func _tick_body(delta: float) -> void:
	if _walking:
		var speed: float = _data.move_speed * _speed_scale
		_walk_angle += speed / WALK_RADIUS * delta
		var centre: Vector3 = _rest_position()
		var spot := centre + Vector3(cos(_walk_angle), 0.0, sin(_walk_angle)) * WALK_RADIUS
		var tangent := Vector3(-sin(_walk_angle), 0.0, cos(_walk_angle))
		_enemy.velocity = tangent * speed
		_enemy.global_position = spot
		_enemy.look_at(spot + tangent, Vector3.UP)
		return
	_enemy.velocity = Vector3.ZERO
	if _turntable:
		_enemy.rotate_y(deg_to_rad(TURNTABLE_DEGREES_PER_SECOND) * delta)


func _tick_camera() -> void:
	var focus: Vector3 = _enemy.global_position \
		+ Vector3.UP * maxf(_data.collision_height * 0.55, 0.4)
	var orbit := Basis.from_euler(Vector3(deg_to_rad(_pitch), deg_to_rad(_yaw), 0.0))
	_camera.global_position = focus + orbit * Vector3(0.0, 0.0, _distance)
	_camera.look_at(focus, Vector3.UP)


# Controls

func _on_walk_toggled(on: bool) -> void:
	_walking = on
	if not on:
		_enemy.global_position = _rest_position()
		_enemy.rotation = Vector3.ZERO


func _on_ability_pressed() -> void:
	if _enemy != null:
		_enemy.ability_used.emit()


## La preparacion del ataque como la ve el jugador: el brillo sube durante
## `attack_windup` y se apaga.
func _on_windup_pressed() -> void:
	if _enemy == null:
		return
	if _windup_tween != null and _windup_tween.is_valid():
		_windup_tween.kill()
	_windup_tween = create_tween()
	_windup_tween.tween_method(_enemy.show_windup, 0.0, 1.0, maxf(_data.attack_windup, 0.4))
	_windup_tween.tween_interval(0.15)
	_windup_tween.tween_callback(_enemy.clear_windup)


## La espoleta sin la cuenta regresiva: con la fisica apagada no hay tick de
## espoleta, asi que se ve el temblor y el brillo sin que explote.
func _on_fuse_toggled(on: bool) -> void:
	if _enemy == null:
		return
	_enemy._fuse_armed = on
	if on:
		_enemy.show_windup(1.0)
	else:
		_enemy.clear_windup()


func _on_hitboxes_toggled(on: bool) -> void:
	_show_hitboxes = on
	if not on:
		_clear_hitbox_meshes()


func _on_clip_pressed(clip: StringName) -> void:
	var motion: Node = _enemy._motion
	if motion != null:
		motion.set_clip_override(clip)


## Relee el `.tres` del arquetipo salteando la cache, para ajustar un modelo
## editando sus valores con el visor abierto. Mantiene el lugar en la lista.
func _on_reload_pressed() -> void:
	if _data == null or _data.resource_path == "":
		return
	var index: int = _archetypes.find(_data)
	var fresh := ResourceLoader.load(_data.resource_path, "",
		ResourceLoader.CACHE_MODE_REPLACE) as EnemyData
	if fresh == null:
		return
	if index >= 0:
		_archetypes[index] = fresh
		var button := _archetype_list.get_child(index) as Button
		if button != null:
			for connection: Dictionary in button.pressed.get_connections():
				button.pressed.disconnect(connection["callable"])
			button.pressed.connect(_show_archetype.bind(fresh))
	# Otro cuerpo: el que habia guarda el modelo del arquetipo viejo, y setup()
	# solo lo reconstruye si cambia la escena del modelo.
	if _enemy != null:
		CombatDirector.unregister(_enemy)
		_enemy.queue_free()
		_enemy = null
	_clear_hitbox_meshes()
	_show_archetype(fresh)


func _on_back_pressed() -> void:
	if _enemy != null:
		CombatDirector.unregister(_enemy)
	GameManager.return_to_menu()


# Hitboxes

## Lo que se golpea, dibujado encima: la capsula del cuerpo que se dispara, la
## esfera de la cabeza y, mas tenue, la capsula de movimiento. Es la forma de ver
## si un modelo flotando o mas ancho que su capsula quedo con zonas intocables.
func _sync_hitboxes() -> void:
	_sync_shape(_enemy.body_hitbox_shape, HITBOX_COLOR)
	_sync_shape(_enemy.head_hitbox_shape, HEAD_COLOR)
	_sync_shape(_enemy.body_shape, BODY_COLOR)


func _sync_shape(node: CollisionShape3D, color: Color) -> void:
	if node == null or node.shape == null:
		return
	var mesh_instance: MeshInstance3D = _hitbox_meshes.get(node)
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.top_level = true
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.no_depth_test = true
		material.albedo_color = color
		mesh_instance.material_override = material
		add_child(mesh_instance)
		_hitbox_meshes[node] = mesh_instance
	var capsule := node.shape as CapsuleShape3D
	var sphere := node.shape as SphereShape3D
	if capsule != null:
		var mesh := mesh_instance.mesh as CapsuleMesh
		if mesh == null:
			mesh = CapsuleMesh.new()
			mesh_instance.mesh = mesh
		mesh.radius = capsule.radius
		mesh.height = capsule.height
	elif sphere != null:
		var mesh := mesh_instance.mesh as SphereMesh
		if mesh == null:
			mesh = SphereMesh.new()
			mesh_instance.mesh = mesh
		mesh.radius = sphere.radius
		mesh.height = sphere.radius * 2.0
	mesh_instance.global_transform = node.global_transform


func _clear_hitbox_meshes() -> void:
	for mesh_instance: MeshInstance3D in _hitbox_meshes.values():
		if is_instance_valid(mesh_instance):
			mesh_instance.queue_free()
	_hitbox_meshes.clear()


# Info

func _rebuild_clip_list() -> void:
	for child: Node in _clip_list.get_children():
		child.queue_free()
	var motion: Node = _enemy._motion
	var clips: Array[StringName] = []
	if motion != null:
		clips = motion.get_clip_names()
	if clips.is_empty():
		var none := Label.new()
		none.theme_type_variation = &"HUDLabel"
		none.text = "Sin clips propios: animacion procedural"
		_clip_list.add_child(none)
		return
	var auto := Button.new()
	auto.text = "AUTO (por estado)"
	auto.tooltip_text = "Deja que el clip lo elija el estado del enemigo, como en el juego."
	auto.pressed.connect(_on_clip_pressed.bind(&""))
	_clip_list.add_child(auto)
	for clip: StringName in clips:
		var button := Button.new()
		button.text = String(clip)
		button.pressed.connect(_on_clip_pressed.bind(clip))
		_clip_list.add_child(button)


func _refresh_info() -> void:
	var model_path: String = _data.model_scene.resource_path.get_file() \
		if _data.model_scene != null else "(capsula grey-box)"
	var fit: String = "alto %.2fm" % _data.model_fit_height if _data.model_fit_height > 0.0 \
		else "escala %.2f" % _data.model_scale
	var lines: PackedStringArray = [
		_data.display_name.to_upper(),
		"HP %d   -   vel %.1f m/s   -   id %s" % [roundi(_data.max_health),
			_data.move_speed, _data.id],
		"Modelo: %s (%s)" % [model_path, fit],
		"Capsula %.2f x %.2f   -   hitbox r %.2f   -   cabeza %.2fm" % [
			_data.collision_height, _data.collision_radius,
			_enemy.get_hitbox_radius(), _data.head_offset],
		"Flota %.2f   bob %.2f @ %.1f/s   giro %.0f/s" % [_data.model_hover_height,
			_data.model_bob_height, _data.model_bob_rate,
			_data.model_spin_degrees_per_second],
		"Inclina %.0f   respira %.3f   pop %.2f" % [_data.model_lean_degrees,
			_data.model_breathe, _data.model_cast_pop],
		"Yaw %.0f   pitch %.0f   halo del modelo: %s" % [_data.model_yaw_degrees,
			_data.model_pitch_degrees, "si" if _data.model_has_halo else "no"],
	]
	_info.text = "\n".join(lines)


func _load_archetypes() -> Array[EnemyData]:
	var out: Array[EnemyData] = []
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		push_error("EnemyViewer: cannot open %s" % DATA_DIR)
		return out
	for file: String in dir.get_files():
		# En un build exportado los .tres vienen como .tres.remap.
		var file_name: String = file.trim_suffix(".remap")
		if not file_name.ends_with(".tres"):
			continue
		var data := load("%s/%s" % [DATA_DIR, file_name]) as EnemyData
		if data != null:
			out.append(data)
	out.sort_custom(func(a: EnemyData, b: EnemyData) -> bool:
		return a.display_name < b.display_name)
	return out


# Construction

func _build_world() -> void:
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.05, 0.06, 0.09)
	sky_material.sky_horizon_color = Color(0.12, 0.13, 0.17)
	sky_material.ground_bottom_color = Color(0.03, 0.03, 0.04)
	sky_material.ground_horizon_color = Color(0.12, 0.13, 0.17)
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.8
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	key.light_energy = 1.3
	key.shadow_enabled = true
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20.0, 150.0, 0.0)
	rim.light_energy = 0.5
	rim.light_color = Color(0.6, 0.8, 1.0)
	add_child(rim)

	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	var shader := Shader.new()
	shader.code = GRID_SHADER
	var grid := ShaderMaterial.new()
	grid.shader = shader
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = plane
	floor_mesh.material_override = grid
	add_child(floor_mesh)

	_camera = Camera3D.new()
	_camera.fov = 55.0
	_camera.current = true
	add_child(_camera)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.theme = THEME
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# Izquierda: arquetipos y volver.
	var left := _panel(root, false, 240.0)
	var left_column := _column(left)
	var title := Label.new()
	title.text = "BESTIARIO"
	title.add_theme_font_size_override(&"font_size", 26)
	left_column.add_child(title)
	_archetype_list = VBoxContainer.new()
	_archetype_list.add_theme_constant_override(&"separation", 6)
	_archetype_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_column.add_child(_archetype_list)
	var back := Button.new()
	back.text = "VOLVER  [ESC]"
	back.pressed.connect(_on_back_pressed)
	left_column.add_child(back)

	# Derecha: estados, clips e info.
	var right := _panel(root, true, 320.0)
	var right_column := _column(right)
	_info = Label.new()
	_info.theme_type_variation = &"HUDLabel"
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_column.add_child(_info)

	var reload := Button.new()
	reload.text = "Recargar .tres desde disco"
	reload.tooltip_text = "Vuelve a leer el EnemyData del disco: ver un cambio sin reiniciar el visor."
	reload.pressed.connect(_on_reload_pressed)
	right_column.add_child(reload)

	right_column.add_child(_section("ESTADO"))
	_walk_toggle = CheckButton.new()
	_walk_toggle.text = "Caminar"
	_walk_toggle.tooltip_text = "Lo hace caminar, para ver el paso y la inclinacion. Al apagarlo vuelve a su lugar."
	_walk_toggle.toggled.connect(_on_walk_toggled)
	right_column.add_child(_walk_toggle)
	var speed_row := HBoxContainer.new()
	var speed_label := Label.new()
	speed_label.theme_type_variation = &"HUDLabel"
	speed_label.text = "Velocidad"
	speed_row.add_child(speed_label)
	var speed := HSlider.new()
	speed.min_value = 0.1
	speed.max_value = 2.0
	speed.step = 0.05
	speed.value = 1.0
	speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed.value_changed.connect(func(value: float) -> void: _speed_scale = value)
	speed_row.add_child(speed)
	right_column.add_child(speed_row)
	var turntable := CheckButton.new()
	turntable.text = "Girar en el lugar"
	turntable.button_pressed = true
	turntable.toggled.connect(func(on: bool) -> void: _turntable = on)
	right_column.add_child(turntable)
	var ability := Button.new()
	ability.text = "Usar habilidad"
	ability.tooltip_text = "La reaccion del modelo al usar su habilidad (ability_used). Solo lo visual."
	ability.pressed.connect(_on_ability_pressed)
	right_column.add_child(ability)
	var windup := Button.new()
	windup.text = "Preparar ataque (windup)"
	windup.tooltip_text = "Muestra el aviso previo al ataque: el brillo que el jugador tiene que leer."
	windup.pressed.connect(_on_windup_pressed)
	right_column.add_child(windup)
	_fuse_toggle = CheckButton.new()
	_fuse_toggle.text = "Espoleta armada"
	_fuse_toggle.tooltip_text = "La espoleta del Bomber: el brillo de aviso encendido."
	_fuse_toggle.toggled.connect(_on_fuse_toggled)
	right_column.add_child(_fuse_toggle)
	var hitboxes := CheckButton.new()
	hitboxes.text = "Mostrar hitboxes"
	hitboxes.tooltip_text = "Dibuja la capsula del cuerpo y la esfera de la cabeza que registran los tiros."
	hitboxes.toggled.connect(_on_hitboxes_toggled)
	right_column.add_child(hitboxes)

	right_column.add_child(_section("CLIPS DEL MODELO"))
	_clip_list = VBoxContainer.new()
	_clip_list.add_theme_constant_override(&"separation", 6)
	right_column.add_child(_clip_list)

	var hint := Label.new()
	hint.theme_type_variation = &"HUDLabel"
	hint.text = "Arrastrar: orbitar   -   Rueda: zoom"
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_top = -40.0
	hint.offset_left = -160.0
	hint.offset_right = 160.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint)


## Una columna de alto completo pegada a un costado.
func _panel(parent: Control, on_right: bool, width: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"HUDPanel"
	parent.add_child(panel)
	var side: float = 1.0 if on_right else 0.0
	panel.anchor_left = side
	panel.anchor_right = side
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -width if on_right else 0.0
	panel.offset_right = 0.0 if on_right else width
	panel.offset_top = 0.0
	panel.offset_bottom = 0.0
	return panel


func _column(panel: PanelContainer) -> VBoxContainer:
	var margin := MarginContainer.new()
	for side: String in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	panel.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	return column


func _section(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"HUDLabel"
	label.text = text
	label.add_theme_color_override(&"font_color", Tokens.REWARD)
	return label
