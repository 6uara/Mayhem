extends SceneTree
## Mide lo que cuestan los numeros de daño flotantes, aislados de todo lo demas.
##
## El playtest reporto que los numeros de daño y el VFX de daño recibido bajan
## los FPS "considerablemente". profile_elite_wave.gd no puede contestar eso: ahi
## los numeros son una fraccion de un cuadro que tambien tiene 27 enemigos,
## particulas y disparos, y lo que se ve es el total. Esta herramienta saca todo
## lo demas del camino y deja una sola variable.
##
## DEBE correr con render real, NUNCA con --headless - headless saltea el
## renderer, y estos numeros son casi todos costo de renderer: cada Label3D es un
## draw call transparente propio.
##
##     godot --path . -s tools/profile_damage_numbers.gd -- [segundos] [hits] [off]
##
## `off` apaga los numeros y mide la misma escena sin ellos: es la linea base
## contra la que el otro numero significa algo. `hits` es cuantos numeros por
## segundo se piden (default 60, que es aproximadamente una escopeta sostenida
## sobre un grupo).

const GAME_SCENE_PATH: String = "res://scenes/main/game.tscn"
const SETTLE_FRAMES: int = 40

var _sample_seconds: float = 12.0
var _hits_per_second: float = 60.0
var _numbers_enabled: bool = true
## Con `hurt` se mide la otra mitad del reporte: el VFX de daño recibido (la
## viñeta roja del HUD y los chevrons direccionales) en vez de los numeros.
var _hurt_mode: bool = false

## Varios objetivos distintos, no uno.
##
## Con un solo objetivo la agregacion del spawner se lleva casi todos los golpes
## y el perfil mide el mejor caso en vez del real. Ocho es aproximadamente lo que
## hay a tiro en una oleada, y obliga a que la mayoria de los golpes pidan un
## numero propio.
const TARGET_COUNT: int = 8

var _game: Node
var _targets: Array[Node3D] = []
var _next_target: int = 0
var _frame: int = 0
var _sampling: bool = false
var _sample_time: float = 0.0
var _hit_debt: float = 0.0
var _emitted: int = 0
var _samples: Array[float] = []


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var positional: Array[String] = []
	for argument: String in args:
		if argument == "off":
			_numbers_enabled = false
		elif argument == "hurt":
			_hurt_mode = true
		else:
			positional.append(argument)
	if positional.size() > 0:
		_sample_seconds = positional[0].to_float()
	if positional.size() > 1:
		_hits_per_second = positional[1].to_float()

	var packed: PackedScene = load(GAME_SCENE_PATH)
	_game = packed.instantiate()
	root.add_child(_game)
	print("Numeros de daño: %s | %.0f hits/s | muestra %.0fs" % [
		"ON" if _numbers_enabled else "OFF", _hits_per_second, _sample_seconds])


func _process(delta: float) -> bool:
	_frame += 1

	if _frame == SETTLE_FRAMES:
		# Igual que profile_elite_wave: el cap de 60 y el vsync techarian la
		# medicion en el refresh del monitor y darian un 60/60/60 inutil.
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		root.get_node("/root/SettingsManager").set_value(
			"hud/damage_numbers", _numbers_enabled)
		_place_target()
		_sampling = true
		return false

	if not _sampling:
		return false

	# Los hits se piden por tiempo y no por frame: pedir uno por frame haria que
	# cuanto mas rapido corre, mas trabajo se pide, y la medicion se perseguiria
	# la cola.
	_hit_debt += _hits_per_second * delta
	while _hit_debt >= 1.0:
		_hit_debt -= 1.0
		_emit_one_hit()

	_sample_time += delta
	_samples.push_back(Engine.get_frames_per_second())
	if _sample_time >= _sample_seconds:
		_report()
		quit()
		return true
	return false


## Un objetivo delante de la camara del jugador. Los numeros salen sobre el, que
## es donde el jugador los mira de verdad: medirlos fuera de pantalla mediria el
## culling, no los numeros.
func _place_target() -> void:
	var players: Array[Node] = root.get_tree().get_nodes_in_group(&"local_player")
	var origin: Vector3 = Vector3(0.0, 1.0, 20.0)
	if not players.is_empty():
		var body := players[0] as Node3D
		origin = body.global_position - body.global_transform.basis.z * 6.0
	for i: int in TARGET_COUNT:
		var target := Node3D.new()
		root.add_child(target)
		# En abanico delante de la camara: todos a la vista, que es donde cuestan.
		target.global_position = origin + Vector3(
			-3.0 + 0.9 * float(i), 0.4 * float(i % 3), 0.6 * float(i % 4))
		_targets.append(target)


func _emit_one_hit() -> void:
	var bus: Node = root.get_node("/root/EventBus")
	if _hurt_mode:
		bus.player_damaged.emit(randf_range(3.0, 12.0), 100.0)
		_emitted += 1
		return
	var target: Node3D = _targets[_next_target]
	_next_target = (_next_target + 1) % _targets.size()
	bus.damage_dealt.emit(target, randf_range(8.0, 140.0), randi() % 4 == 0)
	_emitted += 1


func _report() -> void:
	if _samples.is_empty():
		print("Sin muestras.")
		return
	var total: float = 0.0
	var minimum: float = _samples[0]
	var maximum: float = _samples[0]
	var under_60: int = 0
	for fps: float in _samples:
		total += fps
		minimum = minf(minimum, fps)
		maximum = maxf(maximum, fps)
		if fps < 60.0:
			under_60 += 1

	print("\n--- numeros de daño: %s ---" % ["ON" if _numbers_enabled else "OFF"])
	print("hits emitidos:  %d (%.0f/s pedidos)" % [_emitted, _hits_per_second])
	print("muestras:       %d" % _samples.size())
	print("fps min:        %.1f" % minimum)
	print("fps avg:        %.1f" % (total / float(_samples.size())))
	print("fps max:        %.1f" % maximum)
	print("frames < 60:    %.1f%%" % (100.0 * float(under_60) / float(_samples.size())))
