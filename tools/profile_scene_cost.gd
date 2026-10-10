extends SceneTree
## De donde sale el costo de un frame de partida: FPS y estadisticas del render
## con la escena entera, o sacando partes, para ver cuanto cuesta cada una.
##
## `profile_elite_wave.gd` contesta "llega a 60 con la ola mas cargada"; esto
## contesta "y si no llega, que es lo caro". Mide la arena sin oleada (la
## partida no arranca: sin enemigos, el costo es venue + arena + HUD); para el
## costo con la horda, el otro.
##
##     godot --path . -s tools/profile_scene_cost.gd -- [segundos] [opciones...]
##
## Opciones, combinables:
##   nocrowd     saca el publico
##   nocity      saca la ciudad
##   novenue     saca el coliseo, el techo y la pared de energia
##   noshadows   apaga las sombras del sol
##   noglow      apaga el glow del entorno
##   nohud       esconde la HUD
##   noviewmodel no dibuja el arma en primera persona (su SubViewport aparte)
##   hidehud=X   esconde y apaga el hijo X de la HUD (Reticle, SpeedLines...)
##   freeze=X    apaga el procesamiento del hijo X de game.tscn (HUD, ArenaHost...)
##
## Con render real, nunca --headless. Imprime FPS min/avg/max, draw calls,
## objetos y primitivas por frame. No toca nada versionado.

const GAME_SCENE_PATH: String = "res://scenes/main/game.tscn"
const SETTLE_SECONDS: float = 8.0

var _seconds: float = 10.0
var _options: PackedStringArray = PackedStringArray()
var _game: Node
var _elapsed: float = 0.0
var _phase: int = 0
var _samples: Array[float] = []
var _draw_calls: Array[int] = []
var _objects: Array[int] = []
var _primitives: Array[int] = []
var _cpu_ms: Array[float] = []
var _gpu_ms: Array[float] = []
var _sub_cpu_ms: Array[float] = []


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for argument: String in args:
		if argument.is_valid_float():
			_seconds = argument.to_float()
		else:
			_options.append(argument)
	_game = (load(GAME_SCENE_PATH) as PackedScene).instantiate()
	var tutorial: Node = _game.get_node_or_null("TutorialDirector")
	if tutorial != null:
		tutorial.free()
	# La partida no arranca: se mide la arena vacia.
	var director: Node = _game.get_node_or_null("MatchDirector")
	if director != null:
		director.set("first_wave_delay", 100000.0)
	root.add_child(_game)
	print("profile_scene_cost: %s, options %s" % [GAME_SCENE_PATH, _options])


func _process(delta: float) -> bool:
	_elapsed += delta
	match _phase:
		0:
			# Midiendo el techo real, no el del monitor. Una sola vez: cambiar el
			# modo de vsync recrea la swapchain, y hacerlo cada frame es medir eso.
			if Engine.max_fps != 0:
				Engine.max_fps = 0
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			if _elapsed >= SETTLE_SECONDS:
				_apply_options()
				_phase = 2
				_elapsed = 0.0
		2:
			_keep_player_alive()
			if _elapsed > 0.5:
				_sample(delta)
			if _elapsed >= _seconds + 0.5:
				_report()
				quit(0)
	return false


func _apply_options() -> void:
	for node: Node in _all(_game):
		if node is SubViewport:
			node.add_to_group(&"__profiled_subviewports")
	# `freeze=Nombre` apaga el procesamiento de ese hijo de la escena de juego:
	# para encontrar que script se come el frame sin abrir el profiler.
	for option: String in _options:
		if option.begins_with("hidehud="):
			var widget: CanvasItem = _game.get_node_or_null("HUD/Root/" + option.trim_prefix("hidehud="))
			if widget != null:
				widget.visible = false
				widget.process_mode = Node.PROCESS_MODE_DISABLED
		if option.begins_with("freeze="):
			var target_name: String = option.trim_prefix("freeze=")
			var target: Node = _game.get_node_or_null(target_name)
			if target == null:
				target = root.get_node_or_null(target_name)  # un autoload
			if target != null:
				target.process_mode = Node.PROCESS_MODE_DISABLED
	for node: Node in _all(_game):
		var script: Script = node.get_script()
		var script_name: String = script.resource_path.get_file() if script != null else ""
		if _options.has("nocrowd") and script_name == "crowd_stands.gd":
			(node as Node3D).visible = false
		if _options.has("nocity") and script_name == "city_skyline.gd":
			(node as Node3D).visible = false
		if _options.has("novenue") and script_name in ["arena_coliseum.gd", "arena_roof.gd",
				"energy_wall.gd"]:
			(node as Node3D).visible = false
		if _options.has("noshadows") and node is DirectionalLight3D:
			(node as DirectionalLight3D).shadow_enabled = false
		if _options.has("noglow") and node is WorldEnvironment:
			var env: Environment = (node as WorldEnvironment).environment
			if env != null:
				env.glow_enabled = false
		if _options.has("noviewmodel") and node is SubViewport:
			(node as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
			(node.get_parent() as CanvasItem).visible = false
		if _options.has("nohud") and node is CanvasLayer and node.name == "HUD":
			(node as CanvasLayer).visible = false


func _keep_player_alive() -> void:
	var player: Node = root.get_tree().get_first_node_in_group(&"player")
	if player == null:
		return
	var health: Node = player.get("health")
	if health != null:
		health.set("is_invulnerable", true)


func _sample(delta: float) -> void:
	if delta <= 0.0:
		return
	_samples.append(1.0 / delta)
	# TIME_PROCESS es el frame entero (render incluido); el de fisica si es solo
	# el paso de fisica: scripts de _physics_process, navegacion y Jolt.
	_cpu_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	var viewport: RID = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	var gpu: float = RenderingServer.viewport_get_measured_render_time_gpu(viewport)
	# Los SubViewport (el arma en primera persona) son otro pase entero.
	for node: Node in root.get_tree().get_nodes_in_group(&"__profiled_subviewports"):
		var sub: RID = (node as SubViewport).get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(sub, true)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(sub)
		_sub_cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(sub))
	_gpu_ms.append(gpu)
	_draw_calls.append(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	_objects.append(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
	_primitives.append(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))


func _report() -> void:
	if _samples.is_empty():
		print("No samples.")
		return
	var total: float = 0.0
	var low: float = INF
	var high: float = 0.0
	for fps: float in _samples:
		total += fps
		low = minf(low, fps)
		high = maxf(high, fps)
	print("--- %s ---" % (" ".join(_options) if not _options.is_empty() else "full scene"))
	print("  fps     min %.1f  avg %.1f  max %.1f  (%d frames)" % [
		low, total / _samples.size(), high, _samples.size()])
	var cpu: float = 0.0
	for value: float in _cpu_ms:
		cpu += value
	var gpu: float = 0.0
	for value: float in _gpu_ms:
		gpu += value
	var sub_cpu: float = 0.0
	for value: float in _sub_cpu_ms:
		sub_cpu += value
	print("  subviewports cpu %.2f ms per frame" % (sub_cpu / maxf(_samples.size(), 1.0)))
	print("  physics step %.2f ms  gpu %.2f ms (averages, gpu includes subviewports)" % [
		cpu / maxf(_cpu_ms.size(), 1.0), gpu / maxf(_gpu_ms.size(), 1.0)])
	print("  draw calls %d  objects %d  primitives %d (median)" % [
		_median(_draw_calls), _median(_objects), _median(_primitives)])


func _median(values: Array[int]) -> int:
	if values.is_empty():
		return 0
	var sorted: Array[int] = values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _all(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child: Node in node.get_children():
		out.append_array(_all(child))
	return out
