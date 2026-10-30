extends SceneTree
## Saca fotos del juego real en la arena por defecto, con enemigos encima, para
## comparar un cambio visual con el antes. Juega el flujo normal desde la ola 1
## (sin tutorial) con el jugador invulnerable, y guarda una foto mirando para
## adelante y otra dada vuelta.
##
##     godot --path . --resolution 1600x900 -s tools/capture_arena.gd -- carpeta [segundos] [kill] [weapon=smg] [toon=on|off]
##
## La primera foto mira al enemigo mas cercano. Con `kill` mueren todos justo
## antes, para ver como muere un enemigo.
##
## `toon=on` o `toon=off` fuerza el estilo toon (ver ToonStyle) sin tocar las
## opciones guardadas: para sacar el antes y el despues con la misma semilla.
##
## Deja `carpeta/arena_a.png` y `carpeta/arena_b.png`. `segundos` (default 14) es
## cuanto espera desde que carga hasta la primera foto: tiene que alcanzar para
## que la ola salga por las puertas y se acerque.
##
## Con render de verdad, no --headless (ver capture_menu.gd). No toca nada que
## este en git.

const GAME_SCENE_PATH: String = "res://scenes/main/game.tscn"
## Entre la primera foto y la segunda: lo justo para que el giro se dibuje.
const TURN_SECONDS: float = 0.5
## Desde cuanto antes de la primera foto se gira hacia el enemigo mas cercano.
const AIM_SECONDS: float = 1.0
## Cuanto antes de la primera foto mueren todos con `kill`: lo justo para que
## las esquirlas esten en el aire.
const KILL_LEAD: float = 0.12

var _out_dir: String = "user://"
var _wait: float = 14.0
## Con `kill` como tercer argumento.
var _kill: bool = false
var _killed: bool = false
## Con `weapon=<id>`: el arma en la mano para la foto, en vez de la pistola.
var _weapon_id: StringName = &""
## Con `toon=on/off`: 1 o 0. -1 deja lo que digan las opciones.
var _toon: int = -1
var _armed: bool = false
var _time: float = 0.0
var _game: Node
var _step: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	if args.size() > 1:
		_wait = args[1].to_float()
	_kill = args.has("kill")
	for argument: String in args:
		if argument.begins_with("toon="):
			_toon = 1 if argument == "toon=on" else 0
		if argument.begins_with("weapon="):
			_weapon_id = StringName(argument.trim_prefix("weapon="))
	_game = (load(GAME_SCENE_PATH) as PackedScene).instantiate()
	# Sin tutorial: con el, la ola uno espera a que se termine.
	var tutorial: Node = _game.get_node_or_null("TutorialDirector")
	if tutorial != null:
		tutorial.free()
	root.add_child(_game)


func _process(delta: float) -> bool:
	_time += delta
	if _toon >= 0:
		_force_toon(_toon == 1)
		_toon = -1
	_make_player_invincible()
	if not _armed and _weapon_id != &"" and _time >= 1.0:
		_arm()
	# Mirando al enemigo mas cercano, para que la primera foto tenga a quien
	# mostrar; y matando a todos un instante antes, para que se vea como mueren.
	if _step == 0 and _time >= _wait - AIM_SECONDS:
		_face_nearest_enemy()
	if _step == 0 and _kill and _time >= _wait - KILL_LEAD and not _killed:
		_kill_everyone()
	if _step == 0 and _time >= _wait:
		_save("arena_a.png")
		var player := _player()
		if player != null:
			# El jugador se gira desde su propio yaw cada cuadro: rotarle el nodo no dura.
			player.set("_look_yaw", float(player.get("_look_yaw")) + 180.0)
		_step = 1
	elif _step == 1 and _time >= _wait + TURN_SECONDS:
		_save("arena_b.png")
		_step = 2
		quit()
		return true
	return false


func _face_nearest_enemy() -> void:
	var player := _player()
	if player == null:
		return
	var nearest: Node3D = null
	var best: float = INF
	for node: Node in get_nodes_in_group(&"enemy"):
		var enemy := node as Node3D
		if enemy == null or not enemy.is_visible_in_tree() or not bool(enemy.get("is_active")):
			continue
		var distance: float = enemy.global_position.distance_to(player.global_position)
		if distance < best:
			best = distance
			nearest = enemy
	if nearest == null:
		return
	var flat := Vector3(nearest.global_position.x, player.global_position.y,
		nearest.global_position.z)
	if flat.distance_to(player.global_position) > 0.1:
		var to: Vector3 = flat - player.global_position
		player.set("_look_yaw", rad_to_deg(atan2(-to.x, -to.z)))


func _arm() -> void:
	var player := _player()
	if player == null:
		return
	var holder: Node = player.get("weapon_holder")
	if holder != null:
		holder.call(&"acquire", _weapon_id)
		_armed = true


func _kill_everyone() -> void:
	_killed = true
	for node: Node in get_nodes_in_group(&"enemy"):
		if not bool(node.get("is_active")):
			continue
		var health: Node = node.get("health")
		if health != null:
			health.call("apply_damage", 99999.0)


func _player() -> Node3D:
	var players: Array[Node] = get_nodes_in_group(&"player")
	return players[0] as Node3D if not players.is_empty() else null


## Ver profile_elite_wave.gd: sin esto la ola lo mata antes de la foto.
func _make_player_invincible() -> void:
	var player := _player()
	if player == null:
		return
	var health: Node = player.get("health")
	if health != null:
		health.set("damage_taken_multiplier", 0.0)


func _save(file_name: String) -> void:
	var path: String = _out_dir.path_join(file_name)
	var error: Error = root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("capture_arena: no se pudo guardar %s (%s)" % [path, error_string(error)])
	else:
		print("capture_arena: %s" % path)


## En el primer cuadro y no en _initialize: ahi los autoloads todavia no entraron
## al arbol, y SettingsManager pisaria el valor al cargar las opciones. En
## memoria, sin guardar.
func _force_toon(on: bool) -> void:
	var settings: Node = root.get_node_or_null(^"SettingsManager")
	if settings != null:
		settings.call(&"set_value", "video/toon_style", on)
	var toon: Node = root.get_node_or_null(^"ToonStyle")
	if toon != null:
		toon.call(&"set_enabled", on)
